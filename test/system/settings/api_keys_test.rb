require "application_system_test_case"

# Os rotulos da UI sao traduzidos (default_locale = :"pt-BR") -- resolva cada um
# pela MESMA chave que a view usa, em vez de literais em ingles. Assim o teste
# nao quebra a cada string traduzida nem depende do locale ativo.
#
# Nomes de chave de API ("Test Integration Key"), valores de display_key e o
# trecho do curl sao dados do teste/codigo, nao texto de view -- seguem literais.
class Settings::ApiKeysTest < ApplicationSystemTestCase
  setup do
    @user = users(:family_admin)
    @user.api_keys.destroy_all # Ensure clean state
    login_as @user
  end

  test "should show no API key state when user has no active keys" do
    visit settings_api_key_path

    assert_text I18n.t("settings.api_keys.show.no_api_key.title")
    assert_text I18n.t("settings.api_keys.show.no_api_key.subtitle")
    assert_text I18n.t("settings.api_keys.show.no_api_key.heading")
    assert_link I18n.t("settings.api_keys.show.no_api_key.create_api_key"), href: new_settings_api_key_path
  end

  test "should navigate to create new API key form" do
    visit settings_api_key_path
    click_link I18n.t("settings.api_keys.show.no_api_key.create_api_key")

    assert_current_path new_settings_api_key_path
    assert_text I18n.t("settings.api_keys.new.create_new_key")
    assert_field I18n.t("settings.api_keys.new.name_label")
    assert_text I18n.t("settings.api_keys.new.scope_read")
    assert_text I18n.t("settings.api_keys.new.scope_read_write")
  end

  test "should create a new API key with selected scopes" do
    visit new_settings_api_key_path

    fill_in I18n.t("settings.api_keys.new.name_label"), with: "Test Integration Key"
    choose I18n.t("settings.api_keys.new.scope_read_write")

    click_button I18n.t("settings.api_keys.new.create_key")

    # Should redirect to show page with the API key details
    assert_current_path settings_api_key_path
    assert_text "Test Integration Key"
    assert_text I18n.t("settings.api_keys.show.your_api_key_title")

    # Should show the actual API key value
    api_key_display = find("#api-key-display")
    assert api_key_display.text.length > 30 # Should be a long hex string

    # Should show copy buttons
    assert_button I18n.t("settings.api_keys.show.copy_key")
    assert_link I18n.t("settings.api_keys.show.current_api_key.regenerate_key")
  end

  test "should show current API key details after creation" do
    # Create an API key first
    api_key = ApiKey.create!(
      user: @user,
      name: "Production API Key",
      display_key: "test_plain_key_123",
      scopes: [ "read_write" ]
    )

    visit settings_api_key_path

    assert_text I18n.t("settings.api_keys.show.your_api_key_title")
    assert_text "Production API Key"
    assert_text I18n.t("settings.api_keys.show.current_api_key.active")
    assert_text I18n.t("settings.api_keys.show.current_api_key.scope_read_write")
    assert_text I18n.t("settings.api_keys.show.current_api_key.never_used")
    assert_link I18n.t("settings.api_keys.show.current_api_key.regenerate_key")
    assert_button I18n.t("settings.api_keys.show.current_api_key.revoke_key")
  end

  test "should show usage instructions and example curl command" do
    api_key = ApiKey.create!(
      user: @user,
      name: "Test API Key",
      display_key: "test_key_123",
      scopes: [ "read" ]
    )

    visit settings_api_key_path

    assert_text I18n.t("settings.api_keys.show.usage_instructions_title")
    assert_text "curl -H \"X-Api-Key: test_key_123\""
    assert_text "/api/v1/accounts"
  end

  test "should allow regenerating API key" do
    api_key = ApiKey.create!(
      user: @user,
      name: "Old API Key",
      display_key: "old_key_123",
      scopes: [ "read" ]
    )

    visit settings_api_key_path
    click_link I18n.t("settings.api_keys.show.current_api_key.regenerate_key")

    # Should be on the new API key form
    assert_text I18n.t("settings.api_keys.new.create_new_key")

    fill_in I18n.t("settings.api_keys.new.name_label"), with: "New API Key"
    choose I18n.t("settings.api_keys.new.scope_read")
    click_button I18n.t("settings.api_keys.new.create_key")

    # Should redirect to show page with new key
    assert_text "New API Key"
    assert_text I18n.t("settings.api_keys.show.your_api_key_title")

    # Old key should be revoked
    api_key.reload
    assert api_key.revoked?
  end

  test "should allow revoking API key with confirmation" do
    api_key = ApiKey.create!(
      user: @user,
      name: "Test API Key",
      display_key: "test_key_123",
      scopes: [ "read" ]
    )

    visit settings_api_key_path

    # Click the revoke button to open the modal
    click_button I18n.t("settings.api_keys.show.current_api_key.revoke_key")

    # Wait for the dialog and then confirm
    assert_selector "#confirm-dialog", visible: true
    within "#confirm-dialog" do
      # "Confirm" fica hardcoded no confirm_dialog_controller.js, que sobrescreve
      # em tempo de execucao o texto que o ERB renderiza com
      # t("layouts.shared.confirm_dialog.confirm_button") -- a chave existe, mas
      # nunca chega a tela. Ver reporte.
      click_button "Confirm"
    end

    # Wait for redirect after revoke
    assert_no_selector "#confirm-dialog"

    assert_text I18n.t("settings.api_keys.show.no_api_key.title")
    assert_text I18n.t("settings.api_keys.show.no_api_key.subtitle")

    # Key should be revoked in the database
    api_key.reload
    assert api_key.revoked?
  end

  test "should redirect to show when user already has active key and tries to visit new" do
    api_key = ApiKey.create!(
      user: @user,
      name: "Existing API Key",
      display_key: "existing_key_123",
      scopes: [ "read" ]
    )

    visit new_settings_api_key_path

    assert_current_path settings_api_key_path
  end

  test "should show API key in navigation" do
    visit settings_api_key_path

    within("nav") do
      assert_text I18n.t("settings.settings_nav.api_key_label")
    end
  end

  test "should validate API key name is required" do
    visit new_settings_api_key_path

    # Try to submit without name
    choose I18n.t("settings.api_keys.new.scope_read")
    click_button I18n.t("settings.api_keys.new.create_key")

    # Should stay on form with validation error
    assert_current_path new_settings_api_key_path
    assert_field I18n.t("settings.api_keys.new.name_label") # Form should still be visible
    # The form might not show the validation error inline, but should remain on the form
  end

  test "should show last used timestamp when API key has been used" do
    api_key = ApiKey.create!(
      user: @user,
      name: "Used API Key",
      display_key: "used_key_123",
      scopes: [ "read" ],
      last_used_at: 2.hours.ago
    )

    visit settings_api_key_path

    # A view monta o texto com `t(".current_api_key.last_used", time: time_ago_in_words(...))`.
    # O miolo e traduzido pelo Rails ("aproximadamente 2 horas" em pt-BR), entao a
    # chave inteira ja resolve o rotulo e o tempo juntos.
    assert_text I18n.t(
      "settings.api_keys.show.current_api_key.last_used",
      time: I18n.t("datetime.distance_in_words.about_x_hours", count: 2)
    )
    assert_no_text I18n.t("settings.api_keys.show.current_api_key.never_used")
  end

  test "should show expiration date when API key has expiration" do
    api_key = ApiKey.create!(
      user: @user,
      name: "Expiring API Key",
      display_key: "expiring_key_123",
      scopes: [ "read" ],
      expires_at: 30.days.from_now
    )

    visit settings_api_key_path

    # Should show some indication of expiration (exact format may vary)
    # "Never expires" nao existe em nenhuma view nem no locale -- a asercao e
    # herdada do upstream e passa por vacuidade. Ver reporte.
    assert_no_text "Never expires"
  end
end
