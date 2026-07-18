class Provider::Anthropic::ChatConfig
  # Monta os parametros da Messages API da Anthropic a partir do MESMO contrato
  # que o assistant usa com a OpenAI (prompt + functions + function_results).
  #
  # Diferenca chave: a Responses API da OpenAI e stateful (previous_response_id),
  # entao no follow-up de tool call ela so recebe {call_id, output}. A Anthropic
  # e STATELESS e exige o bloco `tool_use` (com name + input) ANTES do
  # `tool_result` correspondente. O provider guarda os tool_use da resposta
  # anterior e os injeta aqui via `prior_assistant_content`.
  def initialize(
    prompt:,
    instructions: nil,
    functions: [],
    function_results: [],
    prior_assistant_content: nil,
    default_max_tokens: 4096
  )
    @prompt = prompt
    @instructions = instructions
    @functions = functions
    @function_results = function_results
    @prior_assistant_content = prior_assistant_content
    @default_max_tokens = default_max_tokens
  end

  def build_request(model:)
    params = {
      model: model,
      max_tokens: @default_max_tokens,
      messages: build_messages
    }

    system_blocks = build_system_blocks
    params[:system_] = system_blocks if system_blocks.present?

    tool_blocks = build_tools
    params[:tools] = tool_blocks if tool_blocks.present?

    params
  end

  private
    attr_reader :prompt, :instructions, :functions, :function_results, :prior_assistant_content

    def build_messages
      messages = [ { role: "user", content: prompt.to_s } ]

      # Follow-up de tool call: so montamos a troca assistant(tool_use) ->
      # user(tool_result) quando temos AMBOS os lados. Sem os tool_use da
      # resposta anterior, um tool_result orfao seria rejeitado pela Anthropic.
      if prior_assistant_content.present? && function_results.present?
        messages << { role: "assistant", content: tool_use_blocks }
        messages << { role: "user", content: tool_result_blocks }
      end

      messages
    end

    def tool_use_blocks
      prior_assistant_content.map do |req|
        {
          type: "tool_use",
          id: req.call_id,
          name: req.function_name,
          input: parse_arguments(req.function_args)
        }
      end
    end

    def tool_result_blocks
      function_results.map do |result|
        {
          type: "tool_result",
          tool_use_id: result[:call_id],
          content: serialize_output(result[:output])
        }
      end
    end

    def build_system_blocks
      return nil if instructions.blank?

      # System prompt raramente muda dentro de uma sessao; o cache efemero da
      # Anthropic corta ~10x o custo de input nos hits de cache.
      [
        {
          type: "text",
          text: instructions,
          cache_control: { type: "ephemeral" }
        }
      ]
    end

    def build_tools
      return [] if functions.blank?

      functions.map do |fn|
        {
          name: fn[:name],
          description: fn[:description],
          input_schema: anthropic_input_schema(fn[:params_schema])
        }
      end
    end

    # Schemas strict da OpenAI trazem `strict` (so-OpenAI) e frequentemente
    # `additionalProperties: false` (que a Anthropic tambem aceita). Remove
    # `strict` (chave simbolo ou string) para nao vazar campo desconhecido.
    def anthropic_input_schema(schema)
      return schema unless schema.is_a?(Hash)

      schema = schema.deep_dup
      schema.delete(:strict)
      schema.delete("strict")
      schema
    end

    # A Anthropic exige que `tool_use.input` seja um objeto JSON. Normaliza
    # qualquer valor nao-Hash para {} para nao produzir payload rejeitado.
    def parse_arguments(arguments)
      parsed =
        case arguments
        when nil then {}
        when Hash then arguments
        when String
          return {} if arguments.blank?
          JSON.parse(arguments)
        else arguments
        end

      parsed.is_a?(Hash) ? parsed : {}
    rescue JSON::ParserError
      {}
    end

    def serialize_output(output)
      case output
      when nil then ""
      when String then output
      else output.to_json
      end
    end
end
