require "application_system_test_case"

# Os rotulos da UI sao traduzidos (default_locale = :"pt-BR") -- resolva cada um
# pela MESMA chave que a view usa, em vez de literais em ingles.
class TransfersTest < ApplicationSystemTestCase
  setup do
    sign_in @user = users(:family_admin)
    visit transactions_url
  end

  test "can create a transfer" do
    checking_name = accounts(:depository).name
    savings_name = accounts(:credit_card).name
    transfer_date = Date.current

    click_on I18n.t("transactions.index.new_transaction")

    # Will navigate to different route in same modal
    # A aba vem de shared/_transaction_type_tabs, que usa a chave absoluta.
    click_on I18n.t("shared.transaction_tabs.transfer")
    assert_text I18n.t("transfers.new.title")

    select checking_name, from: I18n.t("transfers.form.from")
    select savings_name, from: I18n.t("transfers.form.to")
    fill_in "transfer[amount]", with: 500
    fill_in I18n.t("transfers.form.date"), with: transfer_date

    click_button I18n.t("transfers.form.submit")

    within "#entry-group-" + transfer_date.to_s do
      # Transfer#name monta "Payment to <conta>" hardcoded em ingles no model --
      # a chave transfer.payment_name existe mas nao esta ligada. Sem chave para
      # resolver aqui.
      assert_text "Payment to"
    end
  end
end
