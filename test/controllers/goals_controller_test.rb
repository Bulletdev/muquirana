require "test_helper"

class GoalsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_admin)
    @goal = goals(:emergency_fund)
    @account = accounts(:depository)
  end

  test "should get index" do
    get goals_url
    assert_response :success
  end

  test "should get new" do
    get new_goal_url
    assert_response :success
  end

  test "should get show" do
    get goal_url(@goal)
    assert_response :success
  end

  test "should get edit" do
    get edit_goal_url(@goal)
    assert_response :success
  end

  test "should create goal" do
    assert_difference("Goal.count", 1) do
      post goals_url, params: {
        goal: {
          name: "New car",
          account_id: @account.id,
          target_amount: 30_000,
          target_date: 8.months.from_now.to_date,
          color: "#e99537"
        }
      }
    end

    goal = Goal.order(:created_at).last
    assert_redirected_to goals_url
    assert_equal "USD", goal.currency
    assert_equal @account, goal.account
  end

  test "should not create invalid goal" do
    assert_no_difference("Goal.count") do
      post goals_url, params: {
        goal: { name: "", account_id: @account.id, target_amount: 1000 }
      }
    end

    assert_response :unprocessable_entity
  end

  test "should update goal" do
    patch goal_url(@goal), params: { goal: { name: "Bigger emergency fund" } }
    assert_redirected_to goal_url(@goal)
    assert_equal "Bigger emergency fund", @goal.reload.name
  end

  test "should destroy goal" do
    assert_difference("Goal.count", -1) do
      delete goal_url(@goal)
    end

    assert_redirected_to goals_url
  end

  test "scopes goals to the current family" do
    get goal_url(@goal)
    assert_response :success
    assert_equal @user.family, @goal.family
  end
end
