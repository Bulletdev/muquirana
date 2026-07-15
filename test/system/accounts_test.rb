require "application_system_test_case"

class AccountsTest < ApplicationSystemTestCase
  setup do
    sign_in @user = users(:family_admin)

    Family.any_instance.stubs(:get_link_token).returns("test-link-token")

    visit root_url
    open_new_account_modal
  end

  test "can create depository account" do
    assert_account_created("Depository")
  end

  test "can create investment account" do
    assert_account_created("Investment")
  end

  test "can create crypto account" do
    assert_account_created("Crypto")
  end

  test "can create property account" do
    # Step 1: Select property type and enter basic details
    #
    # O nome do tipo de conta vem do model (accountables.property.display_name_singular),
    # nao de uma chave de view -- e o mesmo metodo que "accounts/_account_type" usa.
    click_link Property.display_name_singular

    account_name = "[system test] Property Account"
    # Os rotulos obrigatorios renderizam com um "*" anexado pelo StyledFormBuilder
    # (ex: "Nome*"). O "*" nao faz parte da chave e o Capybara casa o label por
    # substring, entao a chave crua basta.
    fill_in I18n.t("properties.overview_fields.name"), with: account_name
    # O rotulo da opcao vem de Accountable.long_subtype_label_for (chave
    # accountables.property.subtypes.*.long), o MESMO metodo que o select usa em
    # properties/_overview_fields -- Property::SUBTYPES so guarda o fallback.
    select Property.long_subtype_label_for("single_family_home"),
           from: I18n.t("properties.overview_fields.subtype")
    fill_in I18n.t("properties.overview_fields.year_built"), with: 2005
    fill_in I18n.t("properties.overview_fields.area"), with: 2250

    click_button I18n.t("properties.new.next")

    # Step 2: Enter balance information
    # "Valor" e o rotulo da aba lateral do formulario (properties/_form_tabs).
    assert_text I18n.t("properties.form_tabs.value")
    fill_in "account[balance]", with: 500000
    click_button I18n.t("properties.balances.next")

    # Step 3: Enter address information
    assert_text I18n.t("properties.form_tabs.address")
    fill_in I18n.t("properties.address.line1"), with: "123 Main St"
    fill_in I18n.t("properties.address.locality"), with: "San Francisco"
    fill_in I18n.t("properties.address.region"), with: "CA"
    fill_in I18n.t("properties.address.postal_code"), with: "94101"
    fill_in I18n.t("properties.address.country"), with: "US"

    click_button I18n.t("properties.address.save")

    # Verify account was created and is now active
    assert_text account_name

    created_account = Account.order(:created_at).last
    assert_equal "active", created_account.status
    assert_equal 500000, created_account.balance
    assert_equal "123 Main St", created_account.property.address.line1
    assert_equal "San Francisco", created_account.property.address.locality
  end

  test "can create vehicle account" do
    assert_account_created "Vehicle" do
      fill_in I18n.t("vehicles.form.make"), with: "Toyota"
      fill_in I18n.t("vehicles.form.model"), with: "Camry"
      fill_in I18n.t("vehicles.form.year"), with: "2020"
      fill_in I18n.t("vehicles.form.mileage"), with: "30000"
    end
  end

  test "can create other asset account" do
    assert_account_created("OtherAsset")
  end

  test "can create credit card account" do
    assert_account_created "CreditCard" do
      fill_in I18n.t("credit_cards.form.available_credit"), with: 1000
      fill_in "account[accountable_attributes][minimum_payment]", with: 25.51
      fill_in I18n.t("credit_cards.form.apr"), with: 15.25
      fill_in I18n.t("credit_cards.form.expiration_date"), with: 1.year.from_now.to_date
      fill_in I18n.t("credit_cards.form.annual_fee"), with: 100
    end
  end

  test "can create loan account" do
    assert_account_created "Loan" do
      fill_in "account[accountable_attributes][initial_balance]", with: 1000
      fill_in I18n.t("loans.form.interest_rate"), with: 5.25
      select I18n.t("loans.form.rate_type_fixed"), from: I18n.t("loans.form.rate_type")
      fill_in I18n.t("loans.form.term_months"), with: 360
    end
  end

  test "can create other liability account" do
    assert_account_created("OtherLiability")
  end

  private

    def open_new_account_modal
      within "[data-controller='DS--tabs']" do
        click_button I18n.t("accounts.account_sidebar_tabs.all")
        click_link I18n.t("accounts.account_sidebar_tabs.new_account")
      end
    end

    def assert_account_created(accountable_type, &block)
      # display_name_singular vem do model (accountables.*.display_name_singular),
      # que e o que "accounts/_account_type" renderiza. Nao usar
      # `display_name.singularize`: o singularize aplica regras do ingles e
      # quebra o plural portugues ("Imoveis" -> "Imovei").
      click_link Accountable.from_type(accountable_type).display_name_singular
      click_link I18n.t("accounts.new.method_selector.manual_entry") if accountable_type.in?(%w[Depository Investment Crypto Loan CreditCard])

      account_name = "[system test] #{accountable_type} Account"

      # O campo e obrigatorio, entao o rotulo renderiza "Nome da conta*". O
      # Capybara casa o label por substring, entao a chave crua basta.
      fill_in I18n.t("accounts.form.name_label"), with: account_name
      fill_in "account[balance]", with: 100.99

      yield if block_given?

      # helpers.submit.create ja e traduzido pelo Rails: com locale pt-BR o
      # botao vira "Criar Conta". Resolver pelo I18n mantem o teste valido
      # em qualquer locale.
      click_button I18n.t("helpers.submit.create", model: Account.model_name.human)

      within_testid("account-sidebar-tabs") do
        click_on I18n.t("accounts.account_sidebar_tabs.all")
        find("details", text: Accountable.from_type(accountable_type).display_name).click
        assert_text account_name
      end

      visit accounts_url
      assert_text account_name

      created_account = Account.order(:created_at).last

      visit account_url(created_account)

      within_testid("account-menu") do
        find("button").click
        click_on I18n.t("accounts.show.menu.edit")
      end

      fill_in I18n.t("accounts.form.name_label"), with: "Updated account name"
      click_button I18n.t("helpers.submit.update", model: Account.model_name.human)
      assert_selector "h2", text: "Updated account name"
    end

    def humanized_accountable(accountable_type)
      Accountable.from_type(accountable_type).display_name_singular
    end
end
