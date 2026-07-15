require "application_system_test_case"

class ImportsTest < ApplicationSystemTestCase
  include ActiveJob::TestHelper

  setup do
    sign_in @user = users(:family_admin)

    # Trade securities will be imported as "offline" tickers
    Security.stubs(:provider).returns(nil)
  end

  test "transaction import" do
    visit new_import_path

    click_on I18n.t("imports.new.import_transactions")

    within_testid("import-tabs") do
      click_on I18n.t("import.uploads.show.tab_paste")
    end

    fill_in "import[raw_file_str]", with: file_fixture("imports/transactions.csv").read

    within "form" do
      click_on I18n.t("import.uploads.show.submit")
    end

    # As opcoes dos selects abaixo sao os cabecalhos do CSV de fixture -- dado do
    # arquivo, nao texto de view. So os `from:` (nomes dos campos) e os botoes sao
    # localizados.
    select "Date", from: "import[date_col_label]"
    select "YYYY-MM-DD", from: "import[date_format]"
    select "Amount", from: "import[amount_col_label]"
    select "Account", from: "import[account_col_label]"
    select "Name", from: "import[name_col_label]"
    select "Category", from: "import[category_col_label]"
    select "Tags", from: "import[tags_col_label]"
    select "Notes", from: "import[notes_col_label]"

    click_on I18n.t("import.configurations.transaction_import.submit")

    click_on I18n.t("import.cleans.show.next_step")

    assert_selector "h1", text: I18n.t("import.confirms.show.category_mapping_title")
    click_on I18n.t("import.confirms.mappings.next")

    assert_selector "h1", text: I18n.t("import.confirms.show.tag_mapping_title")
    click_on I18n.t("import.confirms.mappings.next")

    assert_selector "h1", text: I18n.t("import.confirms.show.account_mapping_title")
    click_on I18n.t("import.confirms.mappings.next")

    click_on I18n.t("imports.ready.publish")

    assert_text I18n.t("imports.importing.title")

    perform_enqueued_jobs

    click_on I18n.t("imports.importing.check_status")

    assert_text I18n.t("imports.success.title")

    click_on I18n.t("imports.success.back_to_dashboard")
  end

  test "trade import" do
    visit new_import_path

    click_on I18n.t("imports.new.import_portfolio")

    within_testid("import-tabs") do
      click_on I18n.t("import.uploads.show.tab_paste")
    end

    fill_in "import[raw_file_str]", with: file_fixture("imports/trades.csv").read

    within "form" do
      click_on I18n.t("import.uploads.show.submit")
    end

    select "date", from: "import[date_col_label]"
    select "YYYY-MM-DD", from: "import[date_format]"
    select "qty", from: "import[qty_col_label]"
    select "ticker", from: "import[ticker_col_label]"
    select "price", from: "import[price_col_label]"
    select "account", from: "import[account_col_label]"

    click_on I18n.t("import.configurations.trade_import.submit")

    click_on I18n.t("import.cleans.show.next_step")

    assert_selector "h1", text: I18n.t("import.confirms.show.account_mapping_title")
    click_on I18n.t("import.confirms.mappings.next")

    click_on I18n.t("imports.ready.publish")

    assert_text I18n.t("imports.importing.title")

    perform_enqueued_jobs

    click_on I18n.t("imports.importing.check_status")

    assert_text I18n.t("imports.success.title")

    click_on I18n.t("imports.success.back_to_dashboard")
  end

  test "account import" do
    visit new_import_path

    click_on I18n.t("imports.new.import_accounts")

    within_testid("import-tabs") do
      click_on I18n.t("import.uploads.show.tab_paste")
    end

    fill_in "import[raw_file_str]", with: file_fixture("imports/accounts.csv").read

    within "form" do
      click_on I18n.t("import.uploads.show.submit")
    end

    select "type", from: "import[entity_type_col_label]"
    select "name", from: "import[name_col_label]"
    select "amount", from: "import[amount_col_label]"

    click_on I18n.t("import.configurations.account_import.submit")

    click_on I18n.t("import.cleans.show.next_step")

    assert_selector "h1", text: I18n.t("import.confirms.show.account_type_mapping_title")

    all("form").each do |form|
      within(form) do
        select = form.find("select")
        # "Depository" vem de Import::AccountTypeMapping#selectable_values
        # (Accountable::TYPES.map(&:titleize)) -- valor do model, sem I18n. Ver reporte.
        select "Depository", from: select["id"]
        sleep 0.5
      end
    end

    click_on I18n.t("import.confirms.mappings.next")

    click_on I18n.t("imports.ready.publish")

    assert_text I18n.t("imports.importing.title")

    perform_enqueued_jobs

    click_on I18n.t("imports.importing.check_status")

    assert_text I18n.t("imports.success.title")

    click_on I18n.t("imports.success.back_to_dashboard")
  end

  test "mint import" do
    visit new_import_path

    click_on I18n.t("imports.new.import_mint")

    within_testid("import-tabs") do
      click_on I18n.t("import.uploads.show.tab_paste")
    end

    fill_in "import[raw_file_str]", with: file_fixture("imports/mint.csv").read

    within "form" do
      click_on I18n.t("import.uploads.show.submit")
    end

    click_on I18n.t("import.configurations.mint_import.submit")

    click_on I18n.t("import.cleans.show.next_step")

    assert_selector "h1", text: I18n.t("import.confirms.show.category_mapping_title")
    click_on I18n.t("import.confirms.mappings.next")

    assert_selector "h1", text: I18n.t("import.confirms.show.tag_mapping_title")
    click_on I18n.t("import.confirms.mappings.next")

    assert_selector "h1", text: I18n.t("import.confirms.show.account_mapping_title")
    click_on I18n.t("import.confirms.mappings.next")

    click_on I18n.t("imports.ready.publish")

    assert_text I18n.t("imports.importing.title")

    perform_enqueued_jobs

    click_on I18n.t("imports.importing.check_status")

    assert_text I18n.t("imports.success.title")

    click_on I18n.t("imports.success.back_to_dashboard")
  end
end
