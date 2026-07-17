# frozen_string_literal: true

# Extrai os lancamentos de um extrato/fatura em PDF via LLM.
#
# Le o texto do PDF (pdf-reader), quebra em pedacos para caber no contexto do
# modelo e pede a extracao de cada pedaco em JSON. Deduplica lancamentos que
# aparecem em pedacos consecutivos (artefato do fatiamento).
#
# Prompt afinado para bancos brasileiros: datas dd/mm, valores "R$ 1.234,56"
# (virgula decimal), debitos negativos e creditos positivos.
class Provider::Openai::BankStatementExtractor
  MAX_CHARS_PER_CHUNK = 3000

  attr_reader :client, :pdf_content, :model

  def initialize(client:, pdf_content:, model:)
    @client = client
    @pdf_content = pdf_content
    @model = model
  end

  def extract
    pages = extract_pages_from_pdf
    raise Provider::Openai::Error, "Nao foi possivel extrair texto do PDF" if pages.empty?

    chunks = build_chunks(pages)

    all_transactions = []
    metadata = {}

    chunks.each_with_index do |chunk, index|
      result = process_chunk(chunk, index.zero?)

      tagged = (result[:transactions] || []).map { |t| t.merge(chunk_index: index) }
      all_transactions.concat(tagged)

      if index.zero?
        metadata = {
          account_holder: result[:account_holder],
          account_number: result[:account_number],
          bank_name: result[:bank_name],
          opening_balance: result[:opening_balance],
          closing_balance: result[:closing_balance],
          period: result[:period]
        }
      end

      metadata[:closing_balance] = result[:closing_balance] if result[:closing_balance].present?
    end

    {
      transactions: deduplicate_transactions(all_transactions),
      period: metadata[:period] || {},
      account_holder: metadata[:account_holder],
      account_number: metadata[:account_number],
      bank_name: metadata[:bank_name],
      opening_balance: metadata[:opening_balance],
      closing_balance: metadata[:closing_balance]
    }
  end

  private
    def extract_pages_from_pdf
      return [] if pdf_content.blank?

      reader = PDF::Reader.new(StringIO.new(pdf_content))
      reader.pages.map(&:text).reject(&:blank?)
    rescue => e
      Rails.logger.error("Falha ao extrair texto do PDF: #{e.message}")
      []
    end

    def build_chunks(pages)
      chunks = []
      current = []
      size = 0

      pages.each do |page_text|
        if page_text.length > MAX_CHARS_PER_CHUNK
          chunks << current.join("\n\n") if current.any?
          current = []
          size = 0
          chunks << page_text
          next
        end

        if size + page_text.length > MAX_CHARS_PER_CHUNK && current.any?
          chunks << current.join("\n\n")
          current = []
          size = 0
        end

        current << page_text
        size += page_text.length
      end

      chunks << current.join("\n\n") if current.any?
      chunks
    end

    def process_chunk(text, is_first_chunk)
      response = client.chat(parameters: {
        model: model,
        messages: [
          { role: "system", content: is_first_chunk ? instructions_with_metadata : instructions_transactions_only },
          { role: "user", content: "Extraia os lancamentos:\n\n#{text}" }
        ],
        response_format: { type: "json_object" }
      })

      content = response.dig("choices", 0, "message", "content")
      raise Provider::Openai::Error, "Sem resposta da IA" if content.blank?

      parsed = parse_json_response(content)

      {
        transactions: normalize_transactions(parsed["transactions"] || []),
        period: {
          start_date: parsed.dig("statement_period", "start_date"),
          end_date: parsed.dig("statement_period", "end_date")
        },
        account_holder: parsed["account_holder"],
        account_number: parsed["account_number"],
        bank_name: parsed["bank_name"],
        opening_balance: parsed["opening_balance"],
        closing_balance: parsed["closing_balance"]
      }
    end

    def parse_json_response(content)
      cleaned = content.gsub(%r{^```json\s*}i, "").gsub(/```\s*$/, "").strip
      JSON.parse(cleaned)
    rescue JSON::ParserError => e
      Rails.logger.error("BankStatementExtractor erro de JSON: #{e.message}")
      { "transactions" => [] }
    end

    # Remove lancamentos repetidos na fronteira entre pedacos (artefato do
    # fatiamento). Lancamentos dentro do mesmo pedaco sao sempre preservados.
    def deduplicate_transactions(transactions)
      seen = []
      transactions.select do |t|
        key = [ t[:date], t[:amount], t[:name], t[:chunk_index] ]
        duplicate = seen.any? { |prev| prev[0..2] == key[0..2] && (prev[3] - key[3]).abs <= 1 }
        seen << key
        !duplicate
      end.map { |t| t.except(:chunk_index) }
    end

    def normalize_transactions(transactions)
      transactions.filter_map do |txn|
        date = parse_date(txn["date"])
        amount = parse_amount(txn["amount"])
        next if date.nil? || amount.nil?

        {
          date: date,
          amount: amount,
          name: txn["description"] || txn["name"] || txn["merchant"],
          category: txn["category"] || txn["type"],
          notes: txn["reference"] || txn["notes"]
        }
      end
    end

    def parse_date(date_str)
      return nil if date_str.blank?

      Date.parse(date_str).strftime("%Y-%m-%d")
    rescue ArgumentError, Date::Error
      nil
    end

    # Aceita numero puro ou string "R$ 1.234,56" / "1.234,56" / "-1234.56".
    def parse_amount(amount)
      return nil if amount.nil?
      return amount.to_f if amount.is_a?(Numeric)

      str = amount.to_s.strip
      # Formato brasileiro: ponto de milhar + virgula decimal.
      if str =~ /,\d{1,2}\z/
        str = str.gsub(".", "").gsub(",", ".")
      end
      str = str.gsub(/[^0-9.\-]/, "")
      return nil if str.blank? || str == "-"

      str.to_f
    end

    def instructions_with_metadata
      <<~INSTRUCTIONS.strip
        Extraia os dados do extrato/fatura bancario brasileiro como JSON. Retorne:
        {"bank_name":"...","account_holder":"...","account_number":"ultimos 4 digitos","statement_period":{"start_date":"AAAA-MM-DD","end_date":"AAAA-MM-DD"},"opening_balance":0.00,"closing_balance":0.00,"transactions":[{"date":"AAAA-MM-DD","description":"...","amount":-0.00}]}

        Regras:
        - Valores NEGATIVOS para debitos/despesas/compras, POSITIVOS para creditos/depositos/pagamentos recebidos.
        - Datas no padrao brasileiro (dd/mm ou dd/mm/aaaa) devem ser convertidas para AAAA-MM-DD. Se o ano nao aparecer na linha, use o ano do periodo do extrato.
        - Valores em Reais "R$ 1.234,56" usam ponto como separador de milhar e virgula como decimal; converta para 1234.56.
        - Extraia TODOS os lancamentos.
        - Responda apenas com JSON, sem markdown.
      INSTRUCTIONS
    end

    def instructions_transactions_only
      <<~INSTRUCTIONS.strip
        Extraia os lancamentos do trecho de extrato/fatura bancario brasileiro como JSON. Retorne:
        {"transactions":[{"date":"AAAA-MM-DD","description":"...","amount":-0.00}]}

        Regras:
        - Valores NEGATIVOS para debitos/despesas/compras, POSITIVOS para creditos/depositos.
        - Datas dd/mm(/aaaa) convertidas para AAAA-MM-DD. Valores "R$ 1.234,56" viram 1234.56.
        - Extraia TODOS os lancamentos. Responda apenas com JSON, sem markdown.
      INSTRUCTIONS
    end
end
