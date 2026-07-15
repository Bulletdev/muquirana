require "test_helper"

class DemosControllerTest < ActionDispatch::IntegrationTest
  # O /demo cria uma sessao SEM senha. Numa instancia que nao e de demo isso
  # seria uma porta aberta para dentro do app, entao o mais importante nao e
  # que ele funcione: e que ele NAO exista onde nao deve.
  # O controller levanta RoutingError, mas o Rails a converte em 404 antes de
  # chegar aqui -- por isso o assert e no status, nao na excecao.
  test "demo route 404s outside a demo instance" do
    get demo_url

    assert_response :not_found
  end

  test "demo route does not create a session outside a demo instance" do
    assert_no_difference "Session.count" do
      get demo_url
    end
  end

  test "demo signs the visitor in as the demo user on a demo instance" do
    with_env_overrides DEMO_INSTANCE: "true" do
      demo = users(:family_admin)
      demo.update!(email: Demo::Session::EMAIL)

      assert_difference "Session.count", 1 do
        get demo_url
      end

      assert_redirected_to dashboard_path
    end
  end

  test "demo redirects to login when the instance was never seeded" do
    with_env_overrides DEMO_INSTANCE: "true" do
      assert_nil Demo::Session.user, "fixture nao deve ter o usuario de demo"

      assert_no_difference "Session.count" do
        get demo_url
      end

      assert_redirected_to new_session_path
    end
  end
end
