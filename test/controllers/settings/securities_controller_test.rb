require "test_helper"

class Settings::SecuritiesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:family_admin)
  end

  test "warns about key rotation risk when explicit encryption keys are missing in self-hosted mode" do
    with_self_hosting do
      ActiveRecordEncryptionConfig.stubs(:explicitly_configured?).returns(false)

      get settings_security_url

      assert_response :success
      assert_includes response.body, I18n.t("settings.securities.show.encryption_warning.title")
      # O aviso e sobre PERDA DE DADOS por rotacao de chave, nunca sobre plaintext.
      assert_select "code", text: "ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"
      assert_not_includes response.body.downcase, "plaintext"
    end
  end

  test "does not warn when explicit encryption keys are configured" do
    with_self_hosting do
      ActiveRecordEncryptionConfig.stubs(:explicitly_configured?).returns(true)

      get settings_security_url

      assert_response :success
      assert_not_includes response.body, I18n.t("settings.securities.show.encryption_warning.title")
    end
  end

  test "does not warn in managed mode" do
    get settings_security_url

    assert_response :success
    assert_not_includes response.body, I18n.t("settings.securities.show.encryption_warning.title")
  end
end
