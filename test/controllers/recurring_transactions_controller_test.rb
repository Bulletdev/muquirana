require "test_helper"

class RecurringTransactionsControllerTest < ActionDispatch::IntegrationTest
  include EntriesTestHelper

  setup do
    @user = users(:family_admin)
    sign_in @user
  end

  test "index renders" do
    get recurring_transactions_path
    assert_response :success
  end

  test "index renders with a recurring transaction" do
    @user.family.recurring_transactions.create!(
      name: "Netflix", amount: 30, currency: "USD", expected_day_of_month: 10,
      last_occurrence_date: Date.current, next_expected_date: 1.month.from_now.to_date,
      status: "active", occurrence_count: 3, manual: false
    )
    get recurring_transactions_path
    assert_response :success
  end

  test "identify runs synchronously and redirects" do
    post identify_recurring_transactions_path
    assert_redirected_to recurring_transactions_path
  end

  test "create builds a manual recurring from a transaction" do
    entry = create_transaction(account: accounts(:depository), name: "Aluguel", amount: 1500, currency: "USD")

    assert_difference -> { @user.family.recurring_transactions.count }, 1 do
      post recurring_transactions_path, params: { transaction_id: entry.entryable.id }
    end
  end

  test "toggle_status flips active state" do
    recurring = @user.family.recurring_transactions.create!(
      name: "Netflix", amount: 30, currency: "USD", expected_day_of_month: 10,
      last_occurrence_date: Date.current, next_expected_date: 1.month.from_now.to_date,
      status: "active", occurrence_count: 3, manual: false
    )
    post toggle_status_recurring_transaction_path(recurring)
    assert recurring.reload.inactive?
  end

  test "destroy removes the recurring transaction" do
    recurring = @user.family.recurring_transactions.create!(
      name: "Netflix", amount: 30, currency: "USD", expected_day_of_month: 10,
      last_occurrence_date: Date.current, next_expected_date: 1.month.from_now.to_date,
      status: "active", occurrence_count: 3, manual: false
    )
    assert_difference -> { RecurringTransaction.count }, -1 do
      delete recurring_transaction_path(recurring)
    end
  end
end
