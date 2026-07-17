require "test_helper"

class LlmUsageTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
  end

  test "calculate_cost uses OpenAI pricing per 1M tokens" do
    # gpt-4.1: prompt 2.00 / completion 8.00 por 1M tokens
    cost = LlmUsage.calculate_cost(model: "gpt-4.1", prompt_tokens: 1_000_000, completion_tokens: 1_000_000)
    assert_equal 10.0, cost
  end

  test "calculate_cost matches model by longest prefix first" do
    # snapshot deve casar com a linha especifica gpt-4.1-mini, nao com gpt-4.1
    cost = LlmUsage.calculate_cost(model: "gpt-4.1-mini-2026-03-17", prompt_tokens: 1_000_000, completion_tokens: 0)
    assert_equal 0.4, cost
  end

  test "calculate_cost returns nil for unknown model" do
    assert_nil LlmUsage.calculate_cost(model: "llama-3-local", prompt_tokens: 100, completion_tokens: 100)
  end

  test "provider is always openai" do
    assert_equal "openai", LlmUsage.infer_provider("gpt-4.1")
    assert_equal "openai", LlmUsage.infer_provider("qualquer-modelo")
  end

  test "statistics_for_family aggregates by operation and model" do
    @family.llm_usages.create!(provider: "openai", model: "gpt-4.1", operation: "chat",
                               prompt_tokens: 100, completion_tokens: 50, total_tokens: 150, estimated_cost: 0.10)
    @family.llm_usages.create!(provider: "openai", model: "gpt-4.1", operation: "chat",
                               prompt_tokens: 200, completion_tokens: 100, total_tokens: 300, estimated_cost: 0.20)
    @family.llm_usages.create!(provider: "openai", model: "gpt-4.1-mini", operation: "auto_categorize",
                               prompt_tokens: 300, completion_tokens: 150, total_tokens: 450, estimated_cost: 0.05)
    # Linha sem custo (modelo desconhecido): entra na contagem, fora do custo.
    @family.llm_usages.create!(provider: "openai", model: "custom", operation: "chat",
                               prompt_tokens: 10, completion_tokens: 10, total_tokens: 20, estimated_cost: nil)

    stats = LlmUsage.statistics_for_family(@family)

    assert_equal 4, stats[:total_requests]
    assert_equal 3, stats[:requests_with_cost]
    assert_equal 920, stats[:total_tokens]
    assert_in_delta 0.35, stats[:total_cost], 0.001
    assert_in_delta 0.30, stats[:by_operation]["chat"], 0.001
    assert_in_delta 0.05, stats[:by_operation]["auto_categorize"], 0.001
    assert_in_delta 0.30, stats[:by_model]["gpt-4.1"], 0.001
    assert_in_delta 0.05, stats[:by_model]["gpt-4.1-mini"], 0.001
  end

  test "formatted_cost renders in the family currency (pt-BR BRL)" do
    @family.update!(currency: "BRL")
    usage = @family.llm_usages.create!(provider: "openai", model: "gpt-4.1", operation: "chat",
                                       prompt_tokens: 1, completion_tokens: 1, total_tokens: 2, estimated_cost: 0.05)
    assert_equal "R$0,05", usage.formatted_cost
  end

  test "formatted_cost is nil when there is no estimated cost" do
    usage = @family.llm_usages.create!(provider: "openai", model: "custom", operation: "chat",
                                       prompt_tokens: 1, completion_tokens: 1, total_tokens: 2, estimated_cost: nil)
    assert_nil usage.formatted_cost
  end
end
