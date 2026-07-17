# frozen_string_literal: true

# Classifica um documento PDF financeiro via LLM: define o tipo do documento e
# gera um resumo. Le o texto do PDF com a gem pdf-reader e manda para a OpenAI
# (chat completions com response_format JSON).
#
# Prompt afinado para documentos brasileiros (fatura Nubank, extrato Itau,
# Bradesco, BB, Santander etc.): datas dd/mm/aaaa, valores com virgula decimal e
# "R$".
class Provider::Openai::PdfProcessor
  MAX_TEXT_CHARS = 100_000

  PdfProcessingResult = Provider::LlmConcept::PdfProcessingResult

  attr_reader :client, :model, :pdf_content, :family

  def initialize(client, model:, pdf_content:, family: nil)
    @client = client
    @model = model
    @pdf_content = pdf_content
    @family = family
  end

  def process
    text = extract_text_from_pdf
    raise Provider::Openai::Error, "Nao foi possivel extrair texto do PDF" if text.blank?

    text = text.truncate(MAX_TEXT_CHARS) if text.length > MAX_TEXT_CHARS

    response = client.chat(parameters: {
      model: model,
      messages: [
        { role: "system", content: instructions },
        { role: "user", content: "Analise o texto do documento a seguir e devolva o resumo estruturado:\n\n#{text}" }
      ],
      response_format: { type: "json_object" }
    })

    parse_response(response)
  end

  def instructions
    <<~INSTRUCTIONS.strip
      Voce e um assistente de analise de documentos financeiros brasileiros. Sua
      tarefa e analisar o documento enviado e devolver um resumo estruturado.

      Para cada documento determine:

      1. Tipo do documento (document_type), escolhendo UM entre:
         - bank_statement: extrato de conta bancaria (Itau, Bradesco, Banco do
           Brasil, Santander, Caixa, Nubank Conta, Inter etc.) com lancamentos,
           datas e saldos. Inclui extratos de carteiras digitais e Pix.
         - credit_card_statement: fatura de cartao de credito (fatura Nubank,
           Itaucard, Bradesco, Santander etc.) com compras, pagamentos e total.
         - investment_statement: informe/extrato de investimentos, corretora,
           tesouro, fundos.
         - financial_document: documentos financeiros gerais (nota fiscal,
           recibo, boleto, informe de rendimentos).
         - contract: contratos, termos, documentos de emprestimo/financiamento.
         - other: qualquer coisa que nao se encaixe acima.

      2. Resumo (summary): texto curto em portugues com a instituicao emissora, o
         periodo/competencia, valores relevantes (saldos, total da fatura) e o
         titular (use "Titular" se estiver ocultado).

      3. Dados extraidos (extracted_data): metadados do documento quando for um
         extrato/fatura.

      Regras:
      - Seja factual - relate apenas o que estiver claramente no documento.
      - Datas no padrao brasileiro (dd/mm/aaaa) devem ser convertidas para
        AAAA-MM-DD nos campos de data.
      - Valores em Reais aparecem como "R$ 1.234,56" (ponto como separador de
        milhar, virgula como decimal). Converta para numero decimal com ponto
        (1234.56).
      - Se algo nao estiver visivel, use null.

      Responda SOMENTE com JSON valido neste formato exato (sem blocos de codigo
      markdown, sem texto extra):
      {
        "document_type": "bank_statement|credit_card_statement|investment_statement|financial_document|contract|other",
        "summary": "Resumo claro e conciso do documento...",
        "extracted_data": {
          "institution_name": "Nome do banco/empresa ou null",
          "statement_period_start": "AAAA-MM-DD ou null",
          "statement_period_end": "AAAA-MM-DD ou null",
          "transaction_count": numero ou null,
          "opening_balance": numero ou null,
          "closing_balance": numero ou null,
          "currency": "BRL/USD/etc ou null",
          "account_holder": "Nome ou null"
        }
      }
    INSTRUCTIONS
  end

  private
    def extract_text_from_pdf
      return nil if pdf_content.blank?

      reader = PDF::Reader.new(StringIO.new(pdf_content))
      parts = []
      reader.pages.each_with_index do |page, index|
        parts << "--- Pagina #{index + 1} ---"
        parts << page.text
      end
      parts.join("\n\n")
    rescue => e
      Rails.logger.error("Falha ao extrair texto do PDF: #{e.message}")
      nil
    end

    def parse_response(response)
      raw = response.dig("choices", 0, "message", "content")
      parsed = parse_json_flexibly(raw)

      PdfProcessingResult.new(
        summary: parsed["summary"],
        document_type: normalize_document_type(parsed["document_type"]),
        extracted_data: parsed["extracted_data"] || {}
      )
    end

    def normalize_document_type(doc_type)
      return "other" if doc_type.blank?

      normalized = doc_type.to_s.strip.downcase.gsub(/\s+/, "_")
      Import::DOCUMENT_TYPES.include?(normalized) ? normalized : "other"
    end

    def parse_json_flexibly(raw)
      return {} if raw.blank?

      JSON.parse(raw)
    rescue JSON::ParserError
      if raw =~ /```(?:json)?\s*(\{[\s\S]*?\})\s*```/m
        (JSON.parse($1) rescue nil)&.tap { |h| return h }
      end

      if raw =~ /(\{[\s\S]*\})/m
        (JSON.parse($1) rescue nil)&.tap { |h| return h }
      end

      raise Provider::Openai::Error, "Nao foi possivel interpretar o JSON da resposta: #{raw.truncate(200)}"
    end
end
