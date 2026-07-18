require "test_helper"

class Rule::ActionExecutorTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @family = families(:empty)
    @account = @family.accounts.create!(name: "Checking", balance: 1000, currency: "USD", accountable: Depository.new)
    @target_account = @family.accounts.create!(name: "Savings", balance: 1000, currency: "USD", accountable: Depository.new)
  end

  def build_rule(action_type:, value: nil)
    Rule.create!(
      family: @family,
      resource_type: "transaction",
      effective_date: 1.day.ago.to_date,
      conditions: [ Rule::Condition.new(condition_type: "transaction_account", operator: "=", value: @account.id) ],
      actions: [ Rule::Action.new(action_type: action_type, value: value) ]
    )
  end

  test "exclude_transaction marks matching transactions as excluded" do
    entry = create_transaction(date: Date.current, account: @account)
    other = create_transaction(date: Date.current, account: @target_account)

    rule = build_rule(action_type: "exclude_transaction")
    modified = rule.apply

    assert_equal 1, modified
    assert entry.reload.excluded
    assert_not other.reload.excluded
  end

  test "set_as_transfer_or_payment creates a transfer to the target account" do
    entry = create_transaction(date: Date.current, account: @account, amount: 100)

    rule = build_rule(action_type: "set_as_transfer_or_payment", value: @target_account.id)

    assert_difference "Transfer.count", 1 do
      rule.apply
    end

    assert entry.reload.transaction.transfer?
  end

  test "set_as_transfer_or_payment returns 0 when target account is missing" do
    create_transaction(date: Date.current, account: @account, amount: 100)

    rule = build_rule(action_type: "set_as_transfer_or_payment", value: "nonexistent")

    assert_equal 0, rule.apply
  end
end
