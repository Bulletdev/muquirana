require "test_helper"

class Assistant::Function::CreateGoalTest < ActiveSupport::TestCase
  setup do
    @user = users(:family_admin)
    @account = accounts(:depository) # "Checking Account", dylan_family, USD
    @fn = Assistant::Function::CreateGoal.new(@user)
  end

  test "conta inexistente retorna unknown_account com lista de contas" do
    result = @fn.call("name" => "Viagem", "target_amount" => 5000, "account_name" => "Conta Fantasma", "confirmed" => true)

    assert_not result[:success]
    assert_equal "unknown_account", result[:error]
    assert result[:available_accounts].present?
  end

  test "valor alvo invalido retorna erro" do
    result = @fn.call("name" => "Viagem", "target_amount" => 0, "account_name" => @account.name, "confirmed" => true)
    assert_not result[:success]
    assert_equal "target_amount_invalid", result[:error]
  end

  test "sem confirmacao devolve previa e nao grava" do
    result = nil
    assert_no_difference "Goal.count" do
      result = @fn.call("name" => "Viagem", "target_amount" => 5000, "account_name" => @account.name)
    end

    assert result[:requires_confirmation]
    assert_equal "create_goal", result[:action]
    assert_equal @account.name, result[:preview][:account_name]
  end

  test "com confirmed=true cria a meta ligada a conta da familia" do
    result = nil
    assert_difference "@user.family.goals.count", 1 do
      result = @fn.call("name" => "Viagem", "target_amount" => 5000, "account_name" => @account.name, "confirmed" => true)
    end

    assert result[:success]
    goal = @user.family.goals.find(result[:goal_id])
    assert_equal @account.id, goal.account_id
    assert_equal @account.currency, goal.currency
    assert_equal @user.family_id, goal.account.family_id
  end

  test "nao liga conta de outra familia (isolamento)" do
    alien_family = families(:empty)
    alien = Account.create!(
      family: alien_family,
      name: "Conta Alien",
      balance: 100,
      currency: "USD",
      accountable: Depository.new
    )

    result = nil
    assert_no_difference "Goal.count" do
      result = @fn.call("name" => "Hack", "target_amount" => 1000, "account_name" => alien.name, "confirmed" => true)
    end

    assert_not result[:success]
    assert_equal "unknown_account", result[:error]
  end
end
