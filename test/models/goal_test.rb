require "test_helper"

class GoalTest < ActiveSupport::TestCase
  setup do
    @family = families(:empty)
  end

  # Cria uma conta de deposito com saldo definido, na familia do teste.
  def account_with_balance(balance)
    Account.create!(
      family: @family,
      accountable: Depository.new,
      name: "Savings #{balance}",
      status: "active",
      currency: "USD",
      balance: balance
    )
  end

  def build_goal(attrs = {})
    Goal.new({
      family: @family,
      account: account_with_balance(attrs.delete(:balance) || 0),
      name: "Reserva",
      target_amount: 10_000,
      currency: "USD"
    }.merge(attrs))
  end

  # --- Validacao / criacao ---------------------------------------------------

  test "valid with core attributes" do
    assert build_goal.valid?
  end

  test "requires a name" do
    goal = build_goal(name: nil)
    assert_not goal.valid?
    assert goal.errors[:name].present?
  end

  test "requires a positive target_amount" do
    assert_not build_goal(target_amount: 0).valid?
    assert_not build_goal(target_amount: -5).valid?
  end

  # IDOR: uma conta de outra familia nao pode ser ligada (vazaria o saldo alheio
  # pelo progresso da meta). @family e :empty; a fixture :depository e de outra.
  test "rejects an account from another family" do
    outra_conta = accounts(:depository)
    assert_not_equal @family, outra_conta.family

    goal = build_goal(account: outra_conta)
    assert_not goal.valid?
    assert goal.errors[:account].present?
  end

  test "requires an account" do
    goal = Goal.new(family: @family, name: "Reserva", target_amount: 1000, currency: "USD")
    assert_not goal.valid?
    assert goal.errors[:account].present?
  end

  test "rejects a target_date in the past on create" do
    goal = build_goal(target_date: 1.day.ago.to_date)
    assert_not goal.valid?
    assert goal.errors[:target_date].present?
  end

  # --- Progresso (saldo atual / alvo) ---------------------------------------

  test "progress_percent is current balance over target" do
    goal = build_goal(balance: 2_500, target_amount: 10_000)
    assert_equal 25, goal.progress_percent
    assert_equal 2_500, goal.current_amount
  end

  test "progress_percent caps at 99 until reached" do
    goal = build_goal(balance: 9_999.99, target_amount: 10_000)
    assert_equal 99, goal.progress_percent
    assert_not goal.reached?
  end

  test "progress_percent is 100 when balance meets target" do
    goal = build_goal(balance: 10_000, target_amount: 10_000)
    assert_equal 100, goal.progress_percent
    assert goal.reached?
  end

  test "remaining_amount is clamped at zero when over target" do
    goal = build_goal(balance: 12_000, target_amount: 10_000)
    assert_equal 0, goal.remaining_amount
  end

  # --- Status (saldo vs data-alvo) ------------------------------------------

  test "status is reached when balance meets target regardless of date" do
    goal = build_goal(balance: 10_000, target_amount: 10_000, target_date: 3.months.from_now.to_date)
    assert_equal :reached, goal.status
  end

  test "status is on_track when open-ended (no target date)" do
    goal = build_goal(balance: 100, target_amount: 10_000, target_date: nil)
    assert_equal :on_track, goal.status
  end

  test "status is on_track when balance is ahead of the expected pace" do
    # Metade do prazo decorrido -> esperado ~50% do alvo (5.000).
    goal = build_goal(balance: 6_000, target_amount: 10_000, target_date: 6.months.from_now.to_date)
    goal.save!
    goal.update_column(:created_at, 6.months.ago)

    assert_in_delta 0.5, goal.elapsed_ratio, 0.05
    assert_equal :on_track, goal.status
  end

  test "status is behind when balance trails the expected pace" do
    goal = build_goal(balance: 3_000, target_amount: 10_000, target_date: 6.months.from_now.to_date)
    goal.save!
    goal.update_column(:created_at, 6.months.ago)

    assert_equal :behind, goal.status
  end

  # --- Projecao simples ------------------------------------------------------

  test "monthly_target_amount divides remaining over months left" do
    goal = build_goal(balance: 0, target_amount: 10_000, target_date: 5.months.from_now.to_date)
    assert_operator goal.monthly_target_amount, :>, 0
    assert_nil build_goal(target_date: nil).monthly_target_amount
  end

  test "projected_amount extrapolates current pace to the target date" do
    goal = build_goal(balance: 5_000, target_amount: 10_000, target_date: 6.months.from_now.to_date)
    goal.save!
    goal.update_column(:created_at, 6.months.ago)

    # Metade do prazo com 5.000 guardados -> projecao ~10.000.
    assert_in_delta 10_000, goal.projected_amount, 500
  end
end
