require "test_helper"

class Settings::LlmUsagesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:family_admin)
    sign_in @user
  end

  test "shows the AI usage page" do
    @user.family.llm_usages.create!(provider: "openai", model: "gpt-4.1", operation: "chat",
                                    prompt_tokens: 100, completion_tokens: 50, total_tokens: 150, estimated_cost: 0.10)

    get settings_llm_usage_path
    assert_response :success
  end

  test "shows the AI usage page with no data" do
    get settings_llm_usage_path
    assert_response :success
  end
end
