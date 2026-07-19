class Provider::Anthropic < Provider
  include LlmConcept
  include Concerns::UsageRecorder

  # Subclass so errors caught in this provider are raised as Provider::Anthropic::Error
  Error = Class.new(Provider::Error)

  # Prefixo dos modelos Claude suportados.
  MODEL_PREFIX = "claude".freeze
  DEFAULT_MODEL = "claude-sonnet-5".freeze

  # Modelos oferecidos no dropdown (Configuracoes > Hospedagem propria). Sao
  # aliases -- resolvem para o snapshot mais recente de cada tier. Quem precisar
  # de um id especifico/datado ainda pode setar ANTHROPIC_MODEL, e o valor atual
  # e sempre incluido na lista.
  MODELS = %w[claude-sonnet-5 claude-opus-4-8 claude-haiku-4-5].freeze

  def self.effective_model
    ENV["ANTHROPIC_MODEL"].presence || Setting.anthropic_model.presence || DEFAULT_MODEL
  end

  def initialize(access_token, model: nil)
    client_options = { api_key: access_token }
    client_options[:timeout] = ENV.fetch("ANTHROPIC_REQUEST_TIMEOUT", 600).to_i

    @client = ::Anthropic::Client.new(**client_options)
    @default_model = model.presence || DEFAULT_MODEL

    # A Anthropic e STATELESS: nao existe previous_response_id. Para o follow-up
    # de tool call (que so recebe {call_id, output}) precisamos remontar o turno
    # assistant(tool_use). Guardamos os tool_use de cada resposta por id de
    # resposta; o mesmo provider e reutilizado dentro de um turno pelo Responder.
    @tool_use_cache = {}
  end

  # O assistant roteia por supports_model?; qualquer id "claude*" e nosso.
  def supports_model?(model)
    model.to_s.start_with?(MODEL_PREFIX)
  end

  # Opcoes [label, id] para o seletor de modelo do chat. Usa o modelo efetivo
  # (ENV/Setting/DEFAULT_MODEL) -- quem quiser outro Claude troca ANTHROPIC_MODEL.
  def available_models
    [ [ @default_model, @default_model ] ]
  end

  def supports_pdf_processing?
    false
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

      # Side-effect: registra o custo do auto-categorize. Nunca bloqueia.
      record_usage(
        family: family,
        model: AutoCategorizer::MODEL,
        operation: "auto_categorize",
        usage: categorizer.usage
      )

      result
    end
  end

  def chat_response(prompt, model:, instructions: nil, functions: [], function_results: [], streamer: nil, previous_response_id: nil, family: nil)
    with_provider_response do
      chat_config = ChatConfig.new(
        prompt: prompt,
        instructions: instructions,
        functions: functions,
        function_results: function_results,
        prior_assistant_content: @tool_use_cache[previous_response_id],
        default_max_tokens: default_max_tokens
      )

      request_params = chat_config.build_request(model: model)

      parsed, usage =
        if streamer.present?
          stream_chat_response(streamer: streamer, request_params: request_params)
        else
          sync_chat_response(request_params: request_params)
        end

      cache_tool_use(parsed)

      # Side-effect: registra o uso do chat. Nunca bloqueia a resposta.
      record_usage(family: family, model: model, operation: "chat", usage: usage)

      parsed
    end
  end

  private
    attr_reader :client

    def default_max_tokens
      ENV.fetch("ANTHROPIC_MAX_TOKENS", 4096).to_i
    end

    # Guarda os tool_use (function_requests) da resposta para poder remontar o
    # turno assistant no follow-up (a Anthropic exige tool_use antes de
    # tool_result). Chaveado pelo id que vira o proximo previous_response_id.
    def cache_tool_use(parsed)
      return unless parsed.respond_to?(:function_requests) && parsed.function_requests.any?

      @tool_use_cache[parsed.id] = parsed.function_requests
    end

    def sync_chat_response(request_params:)
      raw = client.messages.create(**request_params)
      parsed = ChatParser.new(raw).parsed
      [ parsed, build_usage_hash(raw.usage) ]
    end

    def stream_chat_response(streamer:, request_params:)
      final_message = nil
      stream = client.messages.stream(**request_params)

      stream.each do |event|
        case event
        when ::Anthropic::Streaming::TextEvent
          streamer.call(
            Provider::LlmConcept::ChatStreamChunk.new(type: "output_text", data: event.text, usage: nil)
          )
        when ::Anthropic::Streaming::MessageStopEvent
          final_message = event.message
        end
      end

      final_message ||= safe_accumulated_message(stream)
      parsed = ChatParser.new(final_message).parsed
      usage = build_usage_hash(final_message&.usage)

      streamer.call(
        Provider::LlmConcept::ChatStreamChunk.new(type: "response", data: parsed, usage: usage)
      )

      [ parsed, usage ]
    end

    def safe_accumulated_message(stream)
      stream.accumulated_message
    rescue StandardError
      nil
    end

    def build_usage_hash(raw_usage)
      return {} unless raw_usage

      input = raw_usage.input_tokens.to_i
      output = raw_usage.output_tokens.to_i
      hash = {
        "input_tokens" => input,
        "output_tokens" => output,
        "total_tokens" => input + output
      }
      hash["cache_creation_input_tokens"] = raw_usage.cache_creation_input_tokens if raw_usage.respond_to?(:cache_creation_input_tokens) && raw_usage.cache_creation_input_tokens
      hash["cache_read_input_tokens"] = raw_usage.cache_read_input_tokens if raw_usage.respond_to?(:cache_read_input_tokens) && raw_usage.cache_read_input_tokens
      hash
    end
end
