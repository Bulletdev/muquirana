require "test_helper"

class RecurringTransactionTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @family = families(:dylan_family)
    @account = accounts(:depository)
  end

  test "requires merchant or name" do
    recurring = RecurringTransaction.new(
      family: @family, amount: 10, currency: "USD",
      expected_day_of_month: 5, last_occurrence_date: Date.current, next_expected_date: Date.current
    )
    assert_not recurring.valid?
    assert recurring.errors.of_kind?(:base, :merchant_or_name_required)
  end

  test "create_from_transaction builds a manual recurring with variance from history" do
    travel_to Date.new(2026, 7, 17) do
      # Historico com pequena variacao de valor no dia 10.
      create_transaction(account: @account, name: "Conta de luz", amount: 100, currency: "USD", date: Date.new(2026, 5, 10))
      create_transaction(account: @account, name: "Conta de luz", amount: 120, currency: "USD", date: Date.new(2026, 6, 10))
      seed = create_transaction(account: @account, name: "Conta de luz", amount: 110, currency: "USD", date: Date.new(2026, 7, 10))

      recurring = RecurringTransaction.create_from_transaction(seed.entryable)

      assert recurring.persisted?
      assert recurring.manual?
      assert_equal "Conta de luz", recurring.name
      assert_equal 10, recurring.expected_day_of_month
      assert recurring.active?
      # Variancia calculada a partir dos 3 lancamentos parecidos.
      assert recurring.has_amount_variance?
      assert_equal 100, recurring.expected_amount_min
      assert_equal 120, recurring.expected_amount_max
      assert_equal Date.new(2026, 8, 10), recurring.next_expected_date
    end
  end

  test "should_be_inactive respects the manual threshold" do
    recurring = @family.recurring_transactions.create!(
      name: "Old sub", amount: 15, currency: "USD", expected_day_of_month: 3,
      last_occurrence_date: 3.months.ago.to_date, next_expected_date: 1.month.from_now.to_date,
      status: "active", occurrence_count: 5, manual: false
    )
    # Automatica: limite de 2 meses -> deve ficar inativa.
    assert recurring.should_be_inactive?

    recurring.update!(manual: true)
    # Manual: limite de 6 meses -> ainda ativa.
    assert_not recurring.should_be_inactive?
  end
end
