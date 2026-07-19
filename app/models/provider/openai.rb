class Provider::Openai < Provider
  include LlmConcept
  include Concerns::UsageRecorder

  # Subclass so errors caught in this provider are raised as Provider::Openai::Error
  Error = Class.new(Provider::Error)

  MODELS = %w[gpt-4.1]

  # Modelo usado para ler PDFs (classificacao + extracao de lancamentos).
  PDF_MODEL = "gpt-4.1"

  def initialize(access_token)
    @client = ::OpenAI::Client.new(access_token: access_token)
  end

  def supports_model?(model)
    MODELS.include?(model)
  end

  # Opcoes [label, id] para o seletor de modelo do chat.
  def available_models
    MODELS.map { |m| [ m, m ] }
  end

  def supports_pdf_processing?
    true
  end

  # Classifica o PDF (tipo de documento + resumo) a partir do texto extraido.
  def process_pdf(pdf_content:, family: nil)
    with_provider_response do
      PdfProcessor.new(
        client,
        model: PDF_MODEL,
        pdf_content: pdf_content,
        family: family
      ).process
    end
  end

  # Extrai os lancamentos de um extrato/fatura em PDF.
  def extract_bank_statement(pdf_content:, family: nil)
    with_provider_response do
      BankStatementExtractor.new(
        client: client,
        pdf_content: pdf_content,
        model: PDF_MODEL
      ).extract
    end
  end

  def auto_categorize(transactions: [], user_categories: [], family: nil)
    with_provider_response do
      raise Error, "Too many transactions to auto-categorize. Max is 25 per request." if transactions.size > 25

      categorizer = AutoCategorizer.new(
        client,
        transactions: transactions,
        user_categories: user_categories
      )

      result = categorizer.auto_categorize

      # Side-effect: registra o custo do auto-categorize (modelo fixo no
      # AutoCategorizer). Nunca bloqueia -- record_usage engole qualquer erro.
      record_usage(
        family: family,
        model: AutoCategorizer::MODEL,
        operation: "auto_categorize",
        usage: categorizer.usage
      )

      result
    end
  end

  def auto_detect_merchants(transactions: [], user_merchants: [])
    with_provider_response do
      raise Error, "Too many transactions to auto-detect merchants. Max is 25 per request." if transactions.size > 25

      AutoMerchantDetector.new(
        client,
        transactions: transactions,
        user_merchants: user_merchants
      ).auto_detect_merchants
    end
  end

  def chat_response(prompt, model:, instructions: nil, functions: [], function_results: [], streamer: nil, previous_response_id: nil, family: nil, user: nil)
    with_provider_response do
      chat_config = ChatConfig.new(
        functions: functions,
        function_results: function_results
      )

      collected_chunks = []

      # Proxy that converts raw stream to "LLM Provider concept" stream
      stream_proxy = if streamer.present?
        proc do |chunk|
          parsed_chunk = ChatStreamParser.new(chunk).parsed

          unless parsed_chunk.nil?
            streamer.call(parsed_chunk)
            collected_chunks << parsed_chunk
          end
        end
      else
        nil
      end

      raw_response = client.responses.create(parameters: {
        model: model,
        input: chat_config.build_input(prompt),
        instructions: instructions,
        tools: chat_config.tools,
        previous_response_id: previous_response_id,
        stream: stream_proxy
      })

      # If streaming, Ruby OpenAI does not return anything, so to normalize this method's API, we search
      # for the "response chunk" in the stream and return it (it is already parsed)
      if stream_proxy.present?
        response_chunk = collected_chunks.find { |chunk| chunk.type == "response" }

        # Cinto de seguranca. O ChatStreamParser ja levanta erro com a mensagem
        # real quando a OpenAI manda um evento de erro; se mesmo assim o stream
        # terminar sem "response", falha com algo legivel em vez de
        # NoMethodError.
        #
        # Era literalmente `response_chunk.data` aqui: com a chave sem credito,
        # o stream nao produzia "response", isso virava
        # "undefined method 'data' for nil" e era esse texto que chegava ao
        # usuario como "Nao foi possivel gerar a resposta".
        if response_chunk.nil?
          raise Error, "A OpenAI encerrou o stream sem devolver resposta. " \
                       "Verifique a chave, a cota e o acesso ao modelo #{model}."
        end

        # Side-effect: registra o uso do chat. Nunca bloqueia a resposta.
        record_usage(family: family, user: user, model: model, operation: "chat", usage: response_chunk.usage)

        response_chunk.data
      else
        parsed = ChatParser.new(raw_response).parsed
        record_usage(family: family, user: user, model: model, operation: "chat", usage: raw_response["usage"])
        parsed
      end
    end
  end

  private
    attr_reader :client
end
