require "test_helper"

class Provider::AnthropicTest < ActiveSupport::TestCase
  include LLMInterfaceTest
  include WebMock::API

  MESSAGES_URL = "https://api.anthropic.com/v1/messages".freeze

  setup do
    @subject = @anthropic = Provider::Anthropic.new(ENV.fetch("ANTHROPIC_ACCESS_TOKEN", "test-anthropic-token"))
    @subject_model = "claude-sonnet-4-6"
  end

  test "roteia apenas modelos claude" do
    assert @anthropic.supports_model?("claude-sonnet-4-6")
    assert @anthropic.supports_model?("claude-haiku-4-5")
    assert_not @anthropic.supports_model?("gpt-4.1")
  end

  test "get_model_provider ignora providers nil e roteia claude para anthropic" do
    # Cenario US-07: so a chave Anthropic setada => openai vem como nil na lista.
    registry = Provider::Registry.for_concept(:llm)
    registry.stubs(:providers).returns([ nil, @anthropic ])
    Provider::Registry.stubs(:for_concept).with(:llm).returns(registry)

    includer = Class.new { include Assistant::Provided }.new
    assert_equal @anthropic, includer.get_model_provider("claude-sonnet-4-6")
  end

  test "chat basico devolve o texto do Claude" do
    stub_messages(body: text_message("Ola do Claude"))

    response = @anthropic.chat_response("Oi", model: @subject_model)

    assert response.success?
    assert_equal "Ola do Claude", response.data.messages.first.output_text
    assert response.data.function_requests.empty?
  end

  test "erros da Anthropic viram Provider::Anthropic::Error" do
    stub_request(:post, MESSAGES_URL).to_return(
      status: 400,
      headers: { "Content-Type" => "application/json" },
      body: { type: "error", error: { type: "invalid_request_error", message: "bad model" } }.to_json
    )

    response = @anthropic.chat_response("Oi", model: "claude-modelo-invalido")

    assert_not response.success?
    assert_kind_of Provider::Anthropic::Error, response.error
  end

  test "parseia tool_use e remonta o turno assistant no follow-up (stateless)" do
    sent_bodies = []
    stub_request(:post, MESSAGES_URL).to_return do |request|
      sent_bodies << JSON.parse(request.body)
      body = sent_bodies.size == 1 ? tool_use_message : text_message("Esta ensolarado em Paris")
      { status: 200, headers: { "Content-Type" => "application/json" }, body: body }
    end

    functions = [ {
      name: "get_weather",
      description: "Get weather for a city",
      params_schema: { type: "object", properties: { city: { type: "string" } }, required: [ "city" ], additionalProperties: false },
      strict: true
    } ]

    first = @anthropic.chat_response("Clima em Paris?", model: @subject_model, functions: functions)
    assert first.success?

    fn = first.data.function_requests.first
    assert_equal "get_weather", fn.function_name
    assert_equal "toolu_01", fn.call_id
    assert_equal({ "city" => "Paris" }, JSON.parse(fn.function_args))

    # Follow-up: o app so passa {call_id, output} + previous_response_id. A
    # Anthropic e stateless, entao o provider precisa remontar o turno tool_use.
    followup = @anthropic.chat_response(
      "Clima em Paris?",
      model: @subject_model,
      functions: functions,
      function_results: [ { call_id: "toolu_01", output: { temp: "24C" } } ],
      previous_response_id: first.data.id
    )
    assert followup.success?
    assert_equal "Esta ensolarado em Paris", followup.data.messages.first.output_text

    followup_msgs = sent_bodies.last["messages"]
    tool_use = followup_msgs.flat_map { |m| Array(m["content"]) }.find { |b| b.is_a?(Hash) && b["type"] == "tool_use" }
    tool_result = followup_msgs.flat_map { |m| Array(m["content"]) }.find { |b| b.is_a?(Hash) && b["type"] == "tool_result" }

    assert_not_nil tool_use, "follow-up deve reenviar o bloco tool_use"
    assert_equal "toolu_01", tool_use["id"]
    assert_equal "get_weather", tool_use["name"]
    assert_not_nil tool_result, "follow-up deve enviar o tool_result"
    assert_equal "toolu_01", tool_result["tool_use_id"]
  end

  test "auto_categorize mapeia via tool call e respeita null" do
    stub_request(:post, MESSAGES_URL).to_return(
      status: 200,
      headers: { "Content-Type" => "application/json" },
      body: categorization_message([
        { "transaction_id" => "1", "category_name" => "Fast Food" },
        { "transaction_id" => "2", "category_name" => nil }
      ])
    )

    response = @anthropic.auto_categorize(
      transactions: [
        { id: "1", name: "McDonalds", amount: 20, classification: "expense" },
        { id: "2", name: "1212XXX charge", amount: 2.99, classification: "expense" }
      ],
      user_categories: [
        { id: "ff", name: "Fast Food", is_subcategory: true, parent_id: nil, classification: "expense" }
      ]
    )

    assert response.success?
    assert_equal "Fast Food", response.data.find { |c| c.transaction_id == "1" }.category_name
    assert_nil response.data.find { |c| c.transaction_id == "2" }.category_name
  end

  test "grava llm_usage com provider anthropic e custo estimado" do
    family = families(:dylan_family)
    stub_messages(body: text_message("Oi", input_tokens: 1_000, output_tokens: 500))

    assert_difference -> { family.llm_usages.count }, 1 do
      @anthropic.chat_response("Oi", model: @subject_model, family: family)
    end

    usage = family.llm_usages.order(:created_at).last
    assert_equal "anthropic", usage.provider
    assert_equal @subject_model, usage.model
    assert_equal "chat", usage.operation
    assert_equal 1_000, usage.prompt_tokens
    assert_equal 500, usage.completion_tokens
    assert_equal 1_500, usage.total_tokens
    # claude-sonnet-4-6: $3/1M input + $15/1M output => 0.003 + 0.0075 = 0.0105
    assert_equal 0.0105, usage.estimated_cost.to_f
  end

  private
    def stub_messages(body:)
      stub_request(:post, MESSAGES_URL).to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: body
      )
    end

    def text_message(text, input_tokens: 12, output_tokens: 7)
      {
        id: "msg_text_01",
        type: "message",
        role: "assistant",
        model: @subject_model,
        content: [ { type: "text", text: text } ],
        stop_reason: "end_turn",
        usage: { input_tokens: input_tokens, output_tokens: output_tokens }
      }.to_json
    end

    def tool_use_message
      {
        id: "msg_tool_01",
        type: "message",
        role: "assistant",
        model: @subject_model,
        content: [ { type: "tool_use", id: "toolu_01", name: "get_weather", input: { city: "Paris" } } ],
        stop_reason: "tool_use",
        usage: { input_tokens: 30, output_tokens: 15 }
      }.to_json
    end

    def categorization_message(categorizations)
      {
        id: "msg_cat_01",
        type: "message",
        role: "assistant",
        model: "claude-haiku-4-5",
        content: [ {
          type: "tool_use",
          id: "toolu_cat",
          name: "report_categorizations",
          input: { categorizations: categorizations }
        } ],
        stop_reason: "tool_use",
        usage: { input_tokens: 50, output_tokens: 20 }
      }.to_json
    end
end
