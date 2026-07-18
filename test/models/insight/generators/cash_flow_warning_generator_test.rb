require "test_helper"

class Insight::Generators::CashFlowWarningGeneratorTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @family = families(:empty)
    @family.update!(currency: "BRL")

    @account = @family.accounts.create!(
      name: "Corrente",
      currency: "BRL",
      balance: 3_000,
      accountable: Depository.new
    )
  end

  # Uma recorrencia mensal de despesa (amount positivo) prevista dentro do horizonte.
  def create_recurring(amount:, days_ahead: 10, currency: "BRL")
    date = Date.current + days_ahead
    @family.recurring_transactions.create!(
      name: "Aluguel",
      amount: amount,
      currency: currency,
      expected_day_of_month: date.day,
      last_occurrence_date: date - 1.month,
      next_expected_date: date,
      status: "active"
    )
  end

  test "warns when projected balance dips low but stays positive" do
    create_recurring(amount: 2_500) # 3.000 - 2.500 = 500, abaixo do limiar e >= 0

    insights = Insight::Generators::CashFlowWarningGenerator.new(@family).generate

    assert_equal 1, insights.size
    insight = insights.first
    assert_equal "cash_flow_warning", insight.insight_type
    assert_equal "medium", insight.priority
    assert_equal "cash_flow_warning.low", insight.template_key
    assert_equal false, insight.metadata[:negative]
    assert_equal "cash_flow_warning:#{Date.current.strftime('%Y-%m')}", insight.dedup_key
  end

  test "warns with high priority when projected balance goes negative" do
    create_recurring(amount: 4_000) # 3.000 - 4.000 = -1.000

    insights = Insight::Generators::CashFlowWarningGenerator.new(@family).generate

    assert_equal 1, insights.size
    insight = insights.first
    assert_equal "high", insight.priority
    assert_equal "cash_flow_warning.negative", insight.template_key
    assert_equal true, insight.metadata[:negative]
  end

  test "stays quiet when the projected balance never drops below the threshold" do
    @account.update!(balance: 50_000)
    create_recurring(amount: 2_500)

    assert_empty Insight::Generators::CashFlowWarningGenerator.new(@family).generate
  end

  test "ignores recurring transactions in another currency" do
    create_recurring(amount: 4_000, currency: "USD")

    # Sem recorrencia na moeda da familia e sem historico de despesa, nada a projetar.
    assert_empty Insight::Generators::CashFlowWarningGenerator.new(@family).generate
  end

  test "produces nothing without any cash accounts" do
    @account.destroy!

    assert_empty Insight::Generators::CashFlowWarningGenerator.new(@family).generate
  end
end
