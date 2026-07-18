require "test_helper"

class Rule::ConditionFilterTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @family = families(:empty)
    @account = @family.accounts.create!(name: "Checking", balance: 1000, currency: "USD", accountable: Depository.new)
    @other_account = @family.accounts.create!(name: "Savings", balance: 1000, currency: "USD", accountable: Depository.new)
    @groceries = @family.categories.create!(name: "Groceries")
  end

  # Builds and persists a rule with a single condition, returning affected resource count
  def affected_count(condition_type:, operator:, value:)
    rule = Rule.create!(
      family: @family,
      resource_type: "transaction",
      effective_date: 1.day.ago.to_date,
      conditions: [ Rule::Condition.new(condition_type: condition_type, operator: operator, value: value) ],
      actions: [ Rule::Action.new(action_type: "set_transaction_category", value: @groceries.id) ]
    )
    rule.affected_resource_count
  end

  test "transaction_account filter matches by account" do
    create_transaction(date: Date.current, account: @account)
    create_transaction(date: Date.current, account: @account)
    create_transaction(date: Date.current, account: @other_account)

    assert_equal 2, affected_count(condition_type: "transaction_account", operator: "=", value: @account.id)
  end

  test "transaction_category filter matches by category" do
    create_transaction(date: Date.current, account: @account, category: @groceries)
    create_transaction(date: Date.current, account: @account)

    assert_equal 1, affected_count(condition_type: "transaction_category", operator: "=", value: @groceries.id)
  end

  test "transaction_category filter with is_null matches uncategorized" do
    create_transaction(date: Date.current, account: @account, category: @groceries)
    create_transaction(date: Date.current, account: @account)

    assert_equal 1, affected_count(condition_type: "transaction_category", operator: "is_null", value: nil)
  end

  test "transaction_type filter distinguishes income and expense" do
    create_transaction(date: Date.current, account: @account, amount: 100)  # expense
    create_transaction(date: Date.current, account: @account, amount: -50)  # income

    assert_equal 1, affected_count(condition_type: "transaction_type", operator: "=", value: "expense")
    assert_equal 1, affected_count(condition_type: "transaction_type", operator: "=", value: "income")
  end

  test "transaction_type filter matches transfers" do
    create_transaction(date: Date.current, account: @account, kind: "funds_movement")
    create_transaction(date: Date.current, account: @account)

    assert_equal 1, affected_count(condition_type: "transaction_type", operator: "=", value: "transfer")
  end

  test "transaction_notes filter searches entry notes" do
    entry = create_transaction(date: Date.current, account: @account)
    entry.update!(notes: "Reimbursed by employer")
    create_transaction(date: Date.current, account: @account)

    assert_equal 1, affected_count(condition_type: "transaction_notes", operator: "like", value: "employer")
  end

  test "transaction_notes filter with is_null matches empty notes" do
    entry = create_transaction(date: Date.current, account: @account)
    entry.update!(notes: "Has a note")
    create_transaction(date: Date.current, account: @account)

    assert_equal 1, affected_count(condition_type: "transaction_notes", operator: "is_null", value: nil)
  end
end
