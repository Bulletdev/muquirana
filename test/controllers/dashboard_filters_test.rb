require "test_helper"

# Os filtros de periodo do painel postam via GET. A raiz e a landing publica e
# o redirect dela para "/painel" descarta a query string -- entao um form
# apontando para root_path perde o filtro em silencio, sem erro, e a tela
# renderiza o default como se nada tivesse sido escolhido.
class DashboardFiltersTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:family_admin)
  end

  # Afirma no que a tela mostra (a opcao marcada no select), nao numa variavel
  # de instancia: e o que o usuario ve, e nao depende da gem rails-controller-
  # testing so para espiar o `assigns`.
  test "cashflow period filter reaches the controller" do
    get dashboard_url(cashflow_period: "last_90_days")

    assert_response :success
    assert_select "select[name=cashflow_period] option[selected][value=?]", "last_90_days"
  end

  test "net worth period filter reaches the controller" do
    get dashboard_url(period: "last_90_days")

    assert_response :success
    assert_select "select[name=period] option[selected][value=?]", "last_90_days"
  end

  # A regressao original: o form apontava para "/" e o parametro morria aqui.
  test "the landing redirect drops query params, so forms must not post to root" do
    get root_url(cashflow_period: "last_90_days")

    assert_redirected_to dashboard_path
    assert_no_match "cashflow_period", response.headers["Location"].to_s,
      "se o redirect passar a preservar params, este teste pode ser revisto"
  end

  test "dashboard filter forms point at the dashboard, not the root" do
    get dashboard_url

    assert_response :success
    # o action dos dois forms de periodo tem que ser /painel.
    # form apontando para "/" perde o parametro no redirect da landing.
    assert_select "form[action=?][method=get]", dashboard_path, minimum: 2
    assert_select "form[action=?][method=get]", root_path, count: 0
  end
end
