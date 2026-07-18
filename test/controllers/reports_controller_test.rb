require "test_helper"

class ReportsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_admin)
  end

  test "index renders net worth and category sections for a family with data" do
    get reports_path
    assert_response :ok
    # dylan_family tem contas e transacoes, entao essas secoes renderizam de fato.
    assert_select "[data-section-key=net_worth]"
    assert_select "[data-section-key=category_breakdown]"
  end

  test "budget performance section renders once the budget is allocated" do
    family = @user.family
    budget = Budget.find_or_bootstrap(family, start_date: Date.current.beginning_of_month)
    budget.update!(budgeted_spending: 5_000, expected_income: 8_000)
    budget.budget_categories.reject(&:subcategory?).first.update!(budgeted_spending: 1_000)

    get reports_path
    assert_response :ok
    assert_select "[data-section-key=budget_performance]"
  end

  test "index shows the empty state for a family without data" do
    sign_in users(:empty)
    get reports_path
    assert_response :ok
    assert_select "[data-section-key]", count: 0
  end

  test "index renders with a period param" do
    get reports_path(period: "last_90_days")
    assert_response :ok
  end

  test "index falls back gracefully on an invalid period" do
    get reports_path(period: "not_a_period")
    assert_response :ok
  end

  test "print renders with the print layout" do
    get print_reports_path
    assert_response :ok
  end

  test "update_preferences persists a collapsed section" do
    patch update_preferences_reports_path,
          params: { preferences: { reports_collapsed_sections: { "net_worth" => true } } },
          as: :json

    assert_response :ok
    assert @user.reload.reports_section_collapsed?("net_worth")
  end

  test "update_preferences persists the section order" do
    new_order = %w[budget_performance net_worth category_breakdown]

    patch update_preferences_reports_path,
          params: { preferences: { reports_section_order: new_order } },
          as: :json

    assert_response :ok
    assert_equal new_order, @user.reload.reports_section_order
  end

  test "update_preferences ignores unknown section keys" do
    patch update_preferences_reports_path,
          params: { preferences: { reports_section_order: %w[net_worth hacker_section] } },
          as: :json

    assert_response :ok
    # Chaves desconhecidas sao descartadas; as secoes conhecidas faltantes
    # voltam ao fim na ordem padrao.
    assert_equal %w[net_worth category_breakdown budget_performance], @user.reload.reports_section_order
  end

  test "collapse toggle merges without dropping the saved order" do
    @user.update_reports_preferences("reports_section_order" => %w[budget_performance category_breakdown net_worth])

    patch update_preferences_reports_path,
          params: { preferences: { reports_collapsed_sections: { "budget_performance" => true } } },
          as: :json

    assert_response :ok
    @user.reload
    assert_equal %w[budget_performance category_breakdown net_worth], @user.reports_section_order
    assert @user.reports_section_collapsed?("budget_performance")
  end
end
