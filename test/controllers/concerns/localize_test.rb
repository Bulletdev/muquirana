require "test_helper"

# O locale era resolvido so por Current.family: visitante sem conta caia sempre
# em pt-BR e a traducao en, completa, era inalcancavel na landing/login.
class LocalizeTest < ActionDispatch::IntegrationTest
  test "visitor gets the default locale without asking for anything" do
    get root_url

    assert_response :success
    assert_match I18n.t("pages.home.headline", locale: :"pt-BR"), response.body
  end

  test "visitor can switch to english with a param" do
    get root_url(locale: "en")

    assert_response :success
    assert_match I18n.t("pages.home.headline", locale: :en), response.body
  end

  test "the choice survives the next page" do
    get root_url(locale: "en")
    get root_url

    assert_response :success
    assert_match I18n.t("pages.home.headline", locale: :en), response.body,
      "sem o cookie, o idioma volta para pt-BR no clique seguinte"
  end

  test "visitor can switch back" do
    get root_url(locale: "en")
    get root_url(locale: "pt-BR")

    assert_match I18n.t("pages.home.headline", locale: :"pt-BR"), response.body
  end

  # locale de fora alimenta lookup de traducao: so a lista branca entra.
  test "rejects a locale outside the whitelist" do
    [ "es", "xx", "../../etc/passwd", "en; DROP", "" ].each do |lixo|
      get root_url(locale: lixo)

      assert_response :success
      assert_match I18n.t("pages.home.headline", locale: :"pt-BR"), response.body,
        "locale #{lixo.inspect} nao devia ser aceito"
    end
  end

  test "a logged in family preference wins over the param" do
    user = users(:family_admin)
    user.family.update!(locale: "en")
    sign_in user

    get dashboard_url(locale: "pt-BR")

    assert_response :success
    assert_equal "en", user.family.reload.locale
  end
end
