require "test_helper"

class Insight::Generators::BudgetInsightGeneratorTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @family = families(:empty)
    @family.update!(currency: "BRL")

    @account = @family.accounts.create!(
      name: "Corrente",
      currency: "BRL",
      balance: 10_000,
      accountable: Depository.new
    )
    @category = @family.categories.create!(name: "Mercado", classification: "expense")
  end

  # Cria o orcamento do mes vigente com uma categoria alocada e gasto real dado.
  def build_budget(budgeted:, spent:, spend_date: Date.current)
    budget = @family.budgets.create!(
      start_date: Date.current.beginning_of_month,
      end_date: Date.current.end_of_month,
      budgeted_spending: budgeted,
      currency: "BRL"
    )
    budget.budget_categories.create!(
      category: @category,
      budgeted_spending: budgeted,
      currency: "BRL"
    )
    create_transaction(account: @account, currency: "BRL", amount: spent, date: spend_date, category: @category) if spent.positive?
    budget
  end

  test "flags a category that went over budget as high priority" do
    travel_to Date.new(2026, 7, 10) do
      build_budget(budgeted: 1_000, spent: 1_500)

      insights = Insight::Generators::BudgetInsightGenerator.new(@family).generate

      assert_equal 1, insights.size
      insight = insights.first
      assert_equal "budget_at_risk", insight.insight_type
      assert_equal "high", insight.priority
      assert_equal "budget_at_risk.over", insight.template_key
      assert_equal @category.name, insight.facts[:categories]
      assert_equal 1, insight.facts[:count]
      assert_equal [ @category.id ], insight.metadata[:over_category_ids]
      assert_equal "budget_at_risk:2026-07", insight.dedup_key
    end
  end

  test "flags a category near its limit as medium priority" do
    travel_to Date.new(2026, 7, 10) do
      build_budget(budgeted: 1_000, spent: 950)

      insights = Insight::Generators::BudgetInsightGenerator.new(@family).generate

      assert_equal 1, insights.size
      insight = insights.first
      assert_equal "budget_at_risk", insight.insight_type
      assert_equal "medium", insight.priority
      assert_equal "budget_at_risk.near", insight.template_key
      assert_equal [ @category.id ], insight.metadata[:near_category_ids]
      assert_empty insight.metadata[:over_category_ids]
    end
  end

  test "emits an on-track signal once the month is half over and everything is within limits" do
    travel_to Date.new(2026, 7, 20) do
      build_budget(budgeted: 1_000, spent: 200)

      insights = Insight::Generators::BudgetInsightGenerator.new(@family).generate

      assert_equal 1, insights.size
      insight = insights.first
      assert_equal "budget_on_track", insight.insight_type
      assert_equal "low", insight.priority
      assert_equal "budget_on_track", insight.template_key
      assert_equal "budget_on_track:2026-07", insight.dedup_key
    end
  end

  test "stays quiet early in the month when nothing is at risk" do
    travel_to Date.new(2026, 7, 3) do
      build_budget(budgeted: 1_000, spent: 200)

      assert_empty Insight::Generators::BudgetInsightGenerator.new(@family).generate
    end
  end

  test "produces nothing when there is no budget for the current month" do
    assert_empty Insight::Generators::BudgetInsightGenerator.new(@family).generate
  end
end
