require "test_helper"

class OnboardableTest < ActionDispatch::IntegrationTest
  # O Onboardable protege o PAINEL, e o painel saiu de "/" para "/painel" --
  # "/" agora e a landing publica. Usar root_path aqui pegaria o redirect da
  # landing para o painel, e nao o do onboarding que este teste verifica.
  setup do
    sign_in @user = users(:empty)
    @user.family.subscription.destroy
  end

  test "must complete onboarding before any other action" do
    @user.update!(onboarded_at: nil)

    get dashboard_path
    assert_redirected_to onboarding_path
  end

  test "must have subscription to visit dashboard" do
    @user.update!(onboarded_at: 1.day.ago)

    get dashboard_path
    assert_redirected_to trial_onboarding_path
  end

  test "onboarded subscribed user can visit dashboard" do
    @user.update!(onboarded_at: 1.day.ago)
    @user.family.start_trial_subscription!

    get dashboard_path
    assert_response :success
  end
end
