require "test_helper"

class Provider::Openai::ChatStreamParserTest < ActiveSupport::TestCase
  # A OpenAI manda o erro como um EVENTO do stream. Antes, type "error" nao
  # casava com nada e `parsed` devolvia nil; o chamador descartava (`unless
  # parsed_chunk.nil?`), o stream terminava sem chunk "response" e o
  # `response_chunk.data` estourava NoMethodError. O usuario recebia
  # "undefined method 'data' for nil" travestido de "nao foi possivel gerar a
  # resposta".
  test "evento de erro vira excecao com a mensagem da OpenAI" do
    evento = {
      "type" => "error",
      "code" => "insufficient_quota",
      "message" => "You exceeded your current quota, please check your plan and billing details."
    }

    erro = assert_raises(Provider::Openai::ChatStreamParser::Error) do
      Provider::Openai::ChatStreamParser.new(evento).parsed
    end

    assert_match(/exceeded your current quota/, erro.message)
    assert_match(/insufficient_quota/, erro.message)
  end

  # E como a gem entrega uma resposta HTTP de erro ao proc de streaming: sem
  # "type", so com "error".
  test "objeto de erro sem type tambem vira excecao" do
    evento = { "error" => { "message" => "Incorrect API key provided", "code" => "invalid_api_key" } }

    erro = assert_raises(Provider::Openai::ChatStreamParser::Error) do
      Provider::Openai::ChatStreamParser.new(evento).parsed
    end

    assert_match(/Incorrect API key/, erro.message)
  end

  test "response.failed diz o motivo" do
    evento = { "type" => "response.failed",
               "response" => { "error" => { "message" => "Rate limit reached" } } }

    erro = assert_raises(Provider::Openai::ChatStreamParser::Error) do
      Provider::Openai::ChatStreamParser.new(evento).parsed
    end

    assert_match(/Rate limit reached/, erro.message)
  end

  # Sem mensagem no payload, ainda tem que sobrar algo legivel -- senao o
  # usuario volta a ficar sem explicacao.
  test "erro sem mensagem ainda produz texto legivel" do
    erro = assert_raises(Provider::Openai::ChatStreamParser::Error) do
      Provider::Openai::ChatStreamParser.new({ "type" => "error" }).parsed
    end

    assert erro.message.present?
    assert_no_match(/^\s*$/, erro.message)
  end

  test "chunk de texto continua sendo parseado" do
    chunk = Provider::Openai::ChatStreamParser.new(
      { "type" => "response.output_text.delta", "delta" => "oi" }
    ).parsed

    assert_equal "output_text", chunk.type
    assert_equal "oi", chunk.data
  end

  test "chunk irrelevante continua ignorado" do
    assert_nil Provider::Openai::ChatStreamParser.new({ "type" => "response.created" }).parsed
    assert_nil Provider::Openai::ChatStreamParser.new({ "type" => "response.in_progress" }).parsed
  end
end
