require "test_helper"

class Provider::Openai::UsageRecorderTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
    @openai = Provider::Openai.new("test-openai-token")
  end

  test "auto_categorize records a usage row after a stubbed OpenAI call" do
    stub_openai_response(
      output_text: { categorizations: [ { transaction_id: "1", category_name: "null" } ] }.to_json,
      usage: { "prompt_tokens" => 400, "completion_tokens" => 100, "total_tokens" => 500 }
    )

    assert_difference -> { @family.llm_usages.count }, 1 do
      response = @openai.auto_categorize(
        transactions: [ { id: "1", name: "Netflix", amount: 30, classification: "expense" } ],
        user_categories: [ { id: "sub", name: "Subscriptions", is_subcategory: false, parent_id: nil, classification: "expense" } ],
        family: @family
      )
      assert response.success?
    end

    usage = @family.llm_usages.recent.first
    assert_equal "openai", usage.provider
    assert_equal Provider::Openai::AutoCategorizer::MODEL, usage.model
    assert_equal "auto_categorize", usage.operation
    assert_equal 400, usage.prompt_tokens
    assert_equal 100, usage.completion_tokens
    assert_equal 500, usage.total_tokens
    # gpt-4.1-mini: 400 * 0.40/1M + 100 * 1.60/1M
    assert_in_delta 0.00032, usage.estimated_cost.to_f, 0.000001
  end

  test "no usage row is recorded when family is absent" do
    stub_openai_response(
      output_text: { categorizations: [] }.to_json,
      usage: { "prompt_tokens" => 1, "completion_tokens" => 1, "total_tokens" => 2 }
    )

    assert_no_difference -> { LlmUsage.count } do
      @openai.auto_categorize(
        transactions: [ { id: "1", name: "Netflix", amount: 30, classification: "expense" } ],
        user_categories: [ { id: "sub", name: "Subscriptions", is_subcategory: false, parent_id: nil, classification: "expense" } ]
      )
    end
  end

  test "recording is a side-effect that never raises even when persistence fails" do
    # Simula falha na gravacao: record_usage precisa engolir o erro.
    LlmUsage.stubs(:calculate_cost).raises(StandardError, "boom")

    assert_nothing_raised do
      @openai.send(:record_usage, family: @family, model: "gpt-4.1", operation: "chat",
                   usage: { "prompt_tokens" => 10, "completion_tokens" => 10, "total_tokens" => 20 })
    end
    assert_equal 0, @family.llm_usages.count
  end

  private
    def stub_openai_response(output_text:, usage:)
      canned = {
        "output" => [ { "content" => [ { "text" => output_text } ] } ],
        "usage" => usage
      }
      responses = mock
      responses.stubs(:create).returns(canned)
      client = mock
      client.stubs(:responses).returns(responses)
      @openai.stubs(:client).returns(client)
    end
end
