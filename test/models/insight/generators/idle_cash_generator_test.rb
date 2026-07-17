require "test_helper"

class Insight::Generators::IdleCashGeneratorTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @family = families(:empty)
    @family.update!(currency: "BRL")
  end

  test "flags a large depository balance with no recent activity" do
    account = @family.accounts.create!(
      name: "Poupanca",
      currency: "BRL",
      balance: 30_000,
      accountable: Depository.new
    )

    insights = Insight::Generators::IdleCashGenerator.new(@family).generate

    assert_equal 1, insights.size
    insight = insights.first
    assert_equal "idle_cash", insight.insight_type
    assert_equal "low", insight.priority
    assert_equal account.id, insight.metadata[:account_id]
    assert_equal 30_000.0, insight.metadata[:balance]
    assert_equal "idle_cash:#{account.id}:#{Date.current.strftime('%Y-%m')}", insight.dedup_key
    assert_equal account.name, insight.facts[:account]
    assert_equal Insight::Generators::IdleCashGenerator::IDLE_DAYS, insight.facts[:idle_days]
  end

  test "ignores balances below the BRL threshold" do
    @family.accounts.create!(
      name: "Conta pequena",
      currency: "BRL",
      balance: Insight::Generators::IdleCashGenerator::MIN_BALANCE - 1,
      accountable: Depository.new
    )

    assert_empty Insight::Generators::IdleCashGenerator.new(@family).generate
  end

  test "ignores accounts with recent activity" do
    account = @family.accounts.create!(
      name: "Conta movimentada",
      currency: "BRL",
      balance: 40_000,
      accountable: Depository.new
    )
    create_transaction(account: account, amount: 100, date: 3.days.ago.to_date)

    assert_empty Insight::Generators::IdleCashGenerator.new(@family).generate
  end
end
