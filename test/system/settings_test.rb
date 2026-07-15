require "application_system_test_case"

class SettingsTest < ApplicationSystemTestCase
  setup do
    sign_in @user = users(:family_admin)

    # O rotulo do link vem do nav de settings; o h1 vem da propria pagina de
    # destino. Sao chaves diferentes (hoje com o mesmo texto em pt-BR), entao
    # cada uma e resolvida pela chave que a view correspondente usa.
    @settings_links = [
      [ I18n.t("settings.settings_nav.profile_label"), I18n.t("settings.profiles.show.page_title"), settings_profile_path ],
      [ I18n.t("settings.settings_nav.preferences_label"), I18n.t("settings.preferences.show.page_title"), settings_preferences_path ],
      [ I18n.t("settings.settings_nav.accounts_label"), I18n.t("accounts.index.accounts"), accounts_path ],
      [ I18n.t("settings.settings_nav.tags_label"), I18n.t("tags.index.tags"), tags_path ],
      [ I18n.t("settings.settings_nav.categories_label"), I18n.t("categories.index.categories"), categories_path ],
      [ I18n.t("settings.settings_nav.merchants_label"), I18n.t("family_merchants.index.title"), family_merchants_path ],
      [ I18n.t("settings.settings_nav.imports_label"), I18n.t("imports.index.title"), imports_path ],
      [ I18n.t("settings.settings_nav.whats_new_label"), I18n.t("pages.changelog.title"), changelog_path ],
      [ I18n.t("settings.settings_nav.feedback_label"), I18n.t("pages.feedback.page_title"), feedback_path ]
    ]
  end

  test "can access settings from sidebar" do
    VCR.use_cassette("git_repository_provider/fetch_latest_release_notes") do
      open_settings_from_sidebar
      assert_selector "h1", text: I18n.t("settings.profiles.show.page_title")
      assert_current_path settings_profile_path, ignore_query: true

      @settings_links.each do |link_label, heading, path|
        click_link link_label
        assert_selector "h1", text: heading
        assert_current_path path
      end
    end
  end

  test "can update self hosting settings" do
    Rails.application.config.app_mode.stubs(:self_hosted?).returns(true)
    Provider::Registry.stubs(:get_provider).with(:synth).returns(nil)
    open_settings_from_sidebar
    assert_selector "li", text: I18n.t("settings.settings_nav.self_hosting_label")
    click_link I18n.t("settings.settings_nav.self_hosting_label")
    assert_current_path settings_hosting_path
    assert_selector "h1", text: I18n.t("settings.hostings.show.title")
    check "setting[require_invite_for_signup]", allow_label_click: true
    click_button I18n.t("settings.hostings.invite_code_settings.generate_tokens")
    assert_selector 'span[data-clipboard-target="source"]', visible: true, count: 1 # invite code copy widget
    copy_button = find('button[data-action="clipboard#copy"]', match: :first) # Find the first copy button (adjust if needed)
    copy_button.click
    assert_selector 'span[data-clipboard-target="iconSuccess"]', visible: true, count: 1 # text copied and icon changed to checkmark
  end

  test "does not show billing link if self hosting" do
    Rails.application.config.app_mode.stubs(:self_hosted?).returns(true)
    open_settings_from_sidebar
    assert_no_selector "li", text: I18n.t("settings.settings_nav.billing_label")
  end

  private

    def open_settings_from_sidebar
      within "div[data-testid=user-menu]" do
        find("button").click
      end
      click_link I18n.t("users.user_menu.settings")
    end
end
