require "test_helper"

class RuleRunTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @family = families(:empty)
    @account = @family.accounts.create!(name: "Checking", balance: 1000, currency: "USD", accountable: Depository.new)
    @groceries = @family.categories.create!(name: "Groceries")
    @rule = Rule.create!(
      family: @family,
      name: "Groceries rule",
      resource_type: "transaction",
      effective_date: 1.day.ago.to_date,
      conditions: [ Rule::Condition.new(condition_type: "transaction_account", operator: "=", value: @account.id) ],
      actions: [ Rule::Action.new(action_type: "set_transaction_category", value: @groceries.id) ]
    )
  end

  test "requires a valid execution_type and status" do
    run = RuleRun.new(rule: @rule, executed_at: Time.current, execution_type: "invalid", status: "success")
    assert_not run.valid?

    run.execution_type = "manual"
    run.status = "bogus"
    assert_not run.valid?

    run.status = "success"
    assert run.valid?
  end

  test "RuleJob records a successful audit run with modified counts" do
    create_transaction(date: Date.current, account: @account)
    create_transaction(date: Date.current, account: @account)

    assert_difference "RuleRun.count", 1 do
      RuleJob.perform_now(@rule, execution_type: "scheduled")
    end

    run = @rule.rule_runs.recent.first
    assert run.success?
    assert_equal "scheduled", run.execution_type
    assert_equal @rule.name, run.rule_name
    assert_equal 2, run.transactions_queued
    assert_equal 2, run.transactions_processed
    assert_equal 2, run.transactions_modified
  end

  test "RuleJob records a failed audit run and re-raises" do
    create_transaction(date: Date.current, account: @account)

    Rule.any_instance.stubs(:apply).raises(StandardError, "boom")

    assert_difference "RuleRun.count", 1 do
      assert_raises(StandardError) do
        RuleJob.perform_now(@rule)
      end
    end

    run = @rule.rule_runs.recent.first
    assert run.failed?
    assert_match "boom", run.error_message
  end
end
