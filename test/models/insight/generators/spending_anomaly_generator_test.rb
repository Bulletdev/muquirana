require "test_helper"

class Insight::Generators::SpendingAnomalyGeneratorTest < ActiveSupport::TestCase
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
    @restaurants = @family.categories.create!(name: "Restaurantes", classification: "expense")
  end

  test "flags a parent category spending well above its 3-month baseline" do
    # 20 de junho: 20 dias decorridos, fator de ritmo 30/20 = 1,5.
    travel_to Date.new(2026, 6, 20) do
      # Baseline: R$ 300/mes nos tres meses completos anteriores -> media 300.
      [ Date.new(2026, 3, 10), Date.new(2026, 4, 10), Date.new(2026, 5, 10) ].each do |date|
        create_transaction(account: @account, amount: 300, date: date, category: @restaurants)
      end
      # Mes atual: R$ 400 ate agora -> projetado 600 -> desvio +100%.
      create_transaction(account: @account, amount: 400, date: Date.new(2026, 6, 5), category: @restaurants)

      insights = Insight::Generators::SpendingAnomalyGenerator.new(@family).generate

      assert_equal 1, insights.size
      insight = insights.first
      assert_equal "spending_anomaly", insight.insight_type
      assert_equal "high", insight.priority # desvio >= 50%
      assert_equal @restaurants.id, insight.metadata[:category_id]
      assert_equal "above", insight.metadata[:direction]
      assert_equal 100, insight.metadata[:deviation_bucket]
      assert_equal 100, insight.facts[:deviation_pct]
      assert_equal @restaurants.name, insight.facts[:category]
      assert_equal "spending_anomaly.above", insight.template_key
      assert_equal "spending_anomaly:#{@restaurants.id}:2026-06", insight.dedup_key
    end
  end

  test "does not flag when spending tracks its baseline" do
    travel_to Date.new(2026, 6, 20) do
      [ Date.new(2026, 3, 10), Date.new(2026, 4, 10), Date.new(2026, 5, 10) ].each do |date|
        create_transaction(account: @account, amount: 300, date: date, category: @restaurants)
      end
      # Ritmo de junho projeta ~300, em linha com a baseline.
      create_transaction(account: @account, amount: 200, date: Date.new(2026, 6, 5), category: @restaurants)

      assert_empty Insight::Generators::SpendingAnomalyGenerator.new(@family).generate
    end
  end

  test "ignores categories whose baseline is below the BRL minimum" do
    travel_to Date.new(2026, 6, 20) do
      # Baseline media de apenas R$ 50/mes, abaixo de MIN_BASELINE (R$ 200).
      [ Date.new(2026, 3, 10), Date.new(2026, 4, 10), Date.new(2026, 5, 10) ].each do |date|
        create_transaction(account: @account, amount: 50, date: date, category: @restaurants)
      end
      create_transaction(account: @account, amount: 500, date: Date.new(2026, 6, 5), category: @restaurants)

      assert_empty Insight::Generators::SpendingAnomalyGenerator.new(@family).generate
    end
  end
end
