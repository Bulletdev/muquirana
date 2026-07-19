require "test_helper"

class Settings::AssistantsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_member)
  end

  test "show renders" do
    get settings_assistant_url
    assert_response :success
  end

  test "update saves the user's own LLM keys (BYOK)" do
    patch settings_assistant_url, params: {
      user: { openai_access_token: "sk-mine", anthropic_access_token: "sk-ant-mine" }
    }

    assert_redirected_to settings_assistant_url
    @user.reload
    assert_equal "sk-mine", @user.openai_access_token
    assert_equal "sk-ant-mine", @user.anthropic_access_token
  end

  test "update can clear a key (blank goes back to instance dependency)" do
    @user.update!(openai_access_token: "sk-old")

    patch settings_assistant_url, params: { user: { openai_access_token: "" } }

    assert_nil @user.reload.openai_access_token.presence
  end
end
