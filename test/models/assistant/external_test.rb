require "test_helper"

class Assistant::ExternalTest < ActiveSupport::TestCase
  include WebMock::API

  setup do
    @chat = chats(:two)
    @message = @chat.messages.create!(
      type: "UserMessage",
      content: "Qual e o meu patrimonio?",
      ai_model: "gpt-4.1"
    )
  end

  teardown do
    # Zera stubs E o historico de requisicoes: sem isto, assert_requested conta
    # cumulativamente as chamadas dos testes anteriores a mesma URL.
    WebMock.reset!

    # Setting e global (RailsSettings): sem isto, uma URL setada aqui vaza para
    # os outros testes e Assistant.for_chat passaria a devolver o externo.
    Setting.external_assistant_url = nil
    Setting.external_assistant_token = nil
    Setting.external_assistant_model = nil
    Setting.external_assistant_agent_id = nil
  end

  # --- Roteamento: sem endpoint cai no fluxo padrao -------------------------

  test "not configured when url is blank" do
    assert_not Assistant::External.configured?
  end

  test "Assistant.for_chat returns the builtin assistant when no external endpoint" do
    assert_instance_of Assistant, Assistant.for_chat(@chat)
  end

  test "configured when url is present via Setting" do
    Setting.external_assistant_url = "http://localhost:11434"
    assert Assistant::External.configured?
  end

  test "Assistant.for_chat routes to external when endpoint configured" do
    Setting.external_assistant_url = "http://localhost:11434"
    assert_instance_of Assistant::External, Assistant.for_chat(@chat)
  end

  # --- Fluxo com endpoint OpenAI-compativel (WebMock) -----------------------

  test "streams a response from an OpenAI-compatible endpoint" do
    Setting.external_assistant_url = "http://localhost:11434/v1/chat/completions"
    Setting.external_assistant_model = "llama3.2"

    stub = stub_request(:post, "http://localhost:11434/v1/chat/completions")
      .with { |req| valid_chat_payload?(req.body) }
      .to_return(
        status: 200,
        headers: { "Content-Type" => "text/event-stream" },
        body: sse_body([ "Seu patrimonio ", "e R$ 124.200" ], model: "llama3.2")
      )

    assert_difference "AssistantMessage.count", 1 do
      Assistant::External.new(@chat).respond_to(@message)
    end

    reply = @chat.messages.ordered.where(type: "AssistantMessage").last
    assert_equal "Seu patrimonio e R$ 124.200", reply.content
    # ai_model e atualizado com o modelo devolvido no stream.
    assert_equal "llama3.2", reply.ai_model
    assert_requested stub
  end

  test "URL without a path is normalized to the OpenAI-compat endpoint" do
    # Usuario informa so o host: o cliente completa /v1/chat/completions.
    Setting.external_assistant_url = "http://localhost:11434"

    stub = stub_request(:post, "http://localhost:11434/v1/chat/completions")
      .to_return(
        status: 200,
        headers: { "Content-Type" => "text/event-stream" },
        body: sse_body([ "ok" ])
      )

    Assistant::External.new(@chat).respond_to(@message)
    assert_requested stub
    assert_equal "ok", @chat.messages.ordered.where(type: "AssistantMessage").last.content
  end

  test "sends no Authorization header when token is blank (local Ollama)" do
    Setting.external_assistant_url = "http://localhost:11434/v1/chat/completions"

    stub = stub_request(:post, "http://localhost:11434/v1/chat/completions")
      .with { |req| req.headers["Authorization"].blank? }
      .to_return(
        status: 200,
        headers: { "Content-Type" => "text/event-stream" },
        body: sse_body([ "ok" ])
      )

    Assistant::External.new(@chat).respond_to(@message)
    assert_requested stub
    assert_equal "ok", @chat.messages.ordered.where(type: "AssistantMessage").last.content
  end

  test "sends Bearer token when configured" do
    Setting.external_assistant_url = "http://localhost:11434/v1/chat/completions"
    Setting.external_assistant_token = "secret-token"

    stub = stub_request(:post, "http://localhost:11434/v1/chat/completions")
      .with(headers: { "Authorization" => "Bearer secret-token" })
      .to_return(
        status: 200,
        headers: { "Content-Type" => "text/event-stream" },
        body: sse_body([ "ok" ])
      )

    Assistant::External.new(@chat).respond_to(@message)
    assert_requested stub
    assert_equal "ok", @chat.messages.ordered.where(type: "AssistantMessage").last.content
  end

  # --- Erros ----------------------------------------------------------------

  test "adds a chat error on upstream HTTP failure and creates no message" do
    Setting.external_assistant_url = "http://localhost:11434/v1/chat/completions"

    stub_request(:post, "http://localhost:11434/v1/chat/completions")
      .to_return(status: 500, body: "boom")

    @chat.expects(:add_error).once

    assert_no_difference "AssistantMessage.count" do
      Assistant::External.new(@chat).respond_to(@message)
    end
  end

  test "adds a chat error when the endpoint returns an empty stream" do
    Setting.external_assistant_url = "http://localhost:11434/v1/chat/completions"

    stub_request(:post, "http://localhost:11434/v1/chat/completions")
      .to_return(
        status: 200,
        headers: { "Content-Type" => "text/event-stream" },
        body: "data: [DONE]\n\n"
      )

    @chat.expects(:add_error).once

    assert_no_difference "AssistantMessage.count" do
      Assistant::External.new(@chat).respond_to(@message)
    end
  end

  private
    def sse_body(contents, model: "local-model")
      lines = contents.map do |content|
        chunk = { model: model, choices: [ { delta: { content: content } } ] }
        "data: #{chunk.to_json}\n\n"
      end
      lines << "data: [DONE]\n\n"
      lines.join
    end

    def valid_chat_payload?(body)
      parsed = JSON.parse(body)
      parsed["stream"] == true &&
        parsed["model"] == "llama3.2" &&
        parsed["messages"].is_a?(Array) &&
        parsed["messages"].first["role"] == "system"
    rescue JSON::ParserError
      false
    end
end
