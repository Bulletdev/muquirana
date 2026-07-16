class Provider::Openai::ChatStreamParser
  Error = Class.new(StandardError)

  def initialize(object)
    @object = object
  end

  def parsed
    type = object.dig("type")

    case type
    when "response.output_text.delta", "response.refusal.delta"
      Chunk.new(type: "output_text", data: object.dig("delta"))
    when "response.completed"
      raw_response = object.dig("response")
      Chunk.new(type: "response", data: parse_response(raw_response))
    when "error"
      # A Responses API manda o erro como um evento do proprio stream. Antes,
      # `type: "error"` nao casava com nada aqui, `parsed` devolvia nil e o
      # chamador descartava o chunk (`unless parsed_chunk.nil?`). O erro real
      # -- "You exceeded your current quota" -- morria em silencio e o usuario
      # via "Nao foi possivel gerar a resposta", sem motivo nenhum.
      raise Error, mensagem_de_erro
    when "response.failed", "response.incomplete"
      raise Error, motivo_da_falha
    else
      # Chunk que nao interessa (response.created, .in_progress, deltas de
      # function call) continua ignorado. Mas objeto com "error" e sem "type"
      # -- que e como uma resposta HTTP de erro chega ao proc de streaming --
      # nao pode passar batido.
      raise Error, mensagem_de_erro if object.dig("error").present?

      nil
    end
  end

  private
    attr_reader :object

    Chunk = Provider::LlmConcept::ChatStreamChunk

    def parse_response(response)
      Provider::Openai::ChatParser.new(response).parsed
    end

    # A OpenAI usa formatos diferentes conforme onde o erro acontece: no evento
    # `error` os campos ficam na raiz; numa resposta HTTP de erro vem aninhado
    # sob "error". Sem um default, a mensagem sairia vazia e o usuario ficaria
    # na mesma situacao de antes -- erro sem explicacao.
    def mensagem_de_erro
      msg = object.dig("error", "message") || object.dig("message")
      codigo = object.dig("error", "code") || object.dig("code")

      [
        msg.presence || "A OpenAI recusou a requisicao",
        codigo.presence && "(#{codigo})"
      ].compact.join(" ")
    end

    def motivo_da_falha
      detalhe = object.dig("response", "error", "message") ||
                object.dig("response", "incomplete_details", "reason")

      [
        "A OpenAI nao concluiu a resposta",
        detalhe.presence && "-- #{detalhe}"
      ].compact.join(" ")
    end
end
