require "test_helper"

class Insight::Generators::SavingsRateChangeGeneratorTest < ActiveSupport::TestCase
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
    @salary = @family.categories.create!(name: "Salario", classification: "income")
    @expenses = @family.categories.create!(name: "Despesas", classification: "expense")
  end

  test "flags a material improvement in the savings rate between the last two complete months" do
    travel_to Date.new(2026, 6, 20) do
      # Abril (mes anterior ao ultimo): renda 1000, despesa 800 -> taxa 20%.
      create_transaction(account: @account, amount: -1000, date: Date.new(2026, 4, 10), category: @salary)
      create_transaction(account: @account, amount: 800, date: Date.new(2026, 4, 15), category: @expenses)
      # Maio (ultimo mes completo): renda 1000, despesa 500 -> taxa 50%.
      create_transaction(account: @account, amount: -1000, date: Date.new(2026, 5, 10), category: @salary)
      create_transaction(account: @account, amount: 500, date: Date.new(2026, 5, 15), category: @expenses)

      insights = Insight::Generators::SavingsRateChangeGenerator.new(@family).generate

      assert_equal 1, insights.size
      insight = insights.first
      assert_equal "savings_rate_change", insight.insight_type
      assert_equal "high", insight.priority # delta de 30pp >= 10pp
      assert_equal "savings_rate_change.up", insight.template_key
      assert_equal 50.0, insight.metadata[:current_rate]
      assert_equal 20.0, insight.metadata[:previous_rate]
      assert_equal 30.0, insight.facts[:change_pp]
      assert_equal "savings_rate_change:2026-05", insight.dedup_key
    end
  end

  test "does not flag a change below the threshold" do
    travel_to Date.new(2026, 6, 20) do
      # Abril: taxa 20%.
      create_transaction(account: @account, amount: -1000, date: Date.new(2026, 4, 10), category: @salary)
      create_transaction(account: @account, amount: 800, date: Date.new(2026, 4, 15), category: @expenses)
      # Maio: taxa 22% (delta de 2pp, abaixo do limiar de 5pp).
      create_transaction(account: @account, amount: -1000, date: Date.new(2026, 5, 10), category: @salary)
      create_transaction(account: @account, amount: 780, date: Date.new(2026, 5, 15), category: @expenses)

      assert_empty Insight::Generators::SavingsRateChangeGenerator.new(@family).generate
    end
  end
end
