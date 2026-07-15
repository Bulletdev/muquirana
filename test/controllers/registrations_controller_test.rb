require "test_helper"

class RegistrationsControllerTest < ActionDispatch::IntegrationTest
  test "new" do
    get new_registration_url
    assert_response :success
  end

  # O link de convite (settings > hospedagem) e a URL de cadastro com
  # ?invite=<token>. Quem recebe nao deve precisar colar o codigo na mao.
  #
  # O preenchimento depende de um `value: params[:invite]` solto na view; sem
  # este teste, some numa refatoracao e o link vira um link comum, sem aviso.
  test "new prefills the invite code from the invite param" do
    with_env_overrides REQUIRE_INVITE_CODE: "true" do
      code = InviteCode.generate!

      get new_registration_url(invite: code)

      assert_response :success
      assert_select "input[name=?][value=?]", "user[invite_code]", code
    end
  end

  test "new leaves the invite code empty without the invite param" do
    with_env_overrides REQUIRE_INVITE_CODE: "true" do
      get new_registration_url

      assert_response :success
      # o campo existe, mas sem valor -- senao o teste acima passaria de graca
      assert_select "input[name=?]", "user[invite_code]"
      assert_select "input[name=?][value]", "user[invite_code]", count: 0
    end
  end

  test "create redirects to correct URL" do
    post registration_url, params: { user: {
      email: "john@example.com",
      password: "Password1!" } }

    assert_redirected_to root_url
  end

  test "create when hosted requires an invite code" do
    with_env_overrides REQUIRE_INVITE_CODE: "true" do
      assert_no_difference "User.count" do
        post registration_url, params: { user: {
          email: "john@example.com",
          password: "Password1!" } }
        assert_redirected_to new_registration_url

        post registration_url, params: { user: {
          email: "john@example.com",
          password: "Password1!",
          invite_code: "foo" } }
        assert_redirected_to new_registration_url
      end

      assert_difference "User.count", +1 do
        post registration_url, params: { user: {
          email: "john@example.com",
          password: "Password1!",
          invite_code: InviteCode.generate! } }
        assert_redirected_to root_url
      end
    end
  end

  # Regressao: o codigo era consumido num before_action, ANTES do save. Um
  # cadastro que falhava na validacao destruia o convite do mesmo jeito, e a
  # pessoa ficava travada -- o link morria sem explicacao na primeira senha
  # fraca digitada.
  test "a failed registration does not burn the invite code" do
    with_env_overrides REQUIRE_INVITE_CODE: "true" do
      code = InviteCode.generate!

      assert_no_difference "User.count" do
        post registration_url, params: { user: {
          email: "novo@exemplo.com",
          password: "fraca",
          password_confirmation: "fraca",
          invite_code: code } }
      end

      assert_not_nil InviteCode.claimable(code),
        "o codigo tem que continuar valendo depois de um cadastro que falhou"
    end
  end

  test "a successful registration records who used the code" do
    with_env_overrides REQUIRE_INVITE_CODE: "true" do
      code = InviteCode.generate!

      assert_difference "User.count", 1 do
        post registration_url, params: { user: {
          email: "convidado@exemplo.com",
          password: "Password1!",
          password_confirmation: "Password1!",
          invite_code: code } }
      end

      registro = InviteCode.find_by(token: code)
      assert registro.used?, "o codigo tem que ficar marcado como usado"
      assert_equal "convidado@exemplo.com", registro.used_by.email,
        "o admin precisa saber QUEM entrou com o convite dele"
      assert_nil InviteCode.claimable(code), "codigo usado nao vale de novo"
    end
  end
end
