require "test_helper"

class RecurringTransaction::IdentifierTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @family = families(:dylan_family)
    @account = accounts(:depository)
  end

  test "detects a clear monthly pattern and records expected day and next date" do
    travel_to Date.new(2026, 7, 17) do
      # Mesma assinatura, todo dia 10, nos ultimos 3 meses.
      [ Date.new(2026, 7, 10), Date.new(2026, 6, 10), Date.new(2026, 5, 10) ].each do |date|
        create_transaction(account: @account, name: "Netflix", amount: 30, currency: "USD", date: date)
      end

      count = RecurringTransaction::Identifier.new(@family).identify_recurring_patterns

      assert_equal 1, count

      recurring = @family.recurring_transactions.find_by(name: "Netflix")
      assert_not_nil recurring
      assert_equal 30, recurring.amount
      assert_equal 10, recurring.expected_day_of_month
      assert_equal 3, recurring.occurrence_count
      assert recurring.active?
      assert_not recurring.manual?
      # Ultima ocorrencia 2026-07-10 -> proxima prevista 2026-08-10.
      assert_equal Date.new(2026, 8, 10), recurring.next_expected_date
      assert_equal Date.new(2026, 7, 10), recurring.last_occurrence_date
    end
  end

  test "ignores series with fewer than 3 occurrences" do
    travel_to Date.new(2026, 7, 17) do
      [ Date.new(2026, 7, 10), Date.new(2026, 6, 10) ].each do |date|
        create_transaction(account: @account, name: "Spotify", amount: 20, currency: "USD", date: date)
      end

      count = RecurringTransaction::Identifier.new(@family).identify_recurring_patterns

      assert_equal 0, count
      assert_nil @family.recurring_transactions.find_by(name: "Spotify")
    end
  end

  test "skips transfer-kind transactions" do
    travel_to Date.new(2026, 7, 17) do
      [ Date.new(2026, 7, 10), Date.new(2026, 6, 10), Date.new(2026, 5, 10) ].each do |date|
        create_transaction(account: @account, name: "Card payment", amount: 500, currency: "USD",
                           date: date, kind: "cc_payment")
      end

      count = RecurringTransaction::Identifier.new(@family).identify_recurring_patterns

      assert_equal 0, count
    end
  end
end
