require "application_system_test_case"

class TradesTest < ApplicationSystemTestCase
  include ActiveJob::TestHelper

  setup do
    sign_in @user = users(:family_admin)

    @user.update!(show_sidebar: false, show_ai_sidebar: false)

    @account = accounts(:investment)

    visit_account_portfolio

    # Disable provider to focus on form testing
    Security.stubs(:provider).returns(nil)
  end

  test "can create buy transaction" do
    shares_qty = 25

    open_new_trade_modal

    fill_in I18n.t("trades.form.holding"), with: "AAPL"
    # "Date" nao tem chave: o campo usa `label: true` e, por ser required, o
    # StyledFormBuilder monta o rotulo com `method.to_s.humanize` em vez de I18n
    # (app/helpers/styled_form_builder.rb:119). Ver reporte.
    fill_in "Date", with: Date.current
    fill_in I18n.t("trades.form.qty"), with: shares_qty
    fill_in "model[price]", with: 214.23

    submit_trade_form

    visit_trades

    within_trades do
      # Trade.build_name monta o nome em ingles e o persiste no banco -- nao
      # passa por I18n. Ver reporte.
      assert_text "Buy #{shares_qty}.0 shares of AAPL"
    end
  end

  test "can create sell transaction" do
    qty = 10
    aapl = @account.holdings.find { |h| h.security.ticker == "AAPL" }

    open_new_trade_modal

    select I18n.t("trades.form.type_sell"), from: I18n.t("trades.form.type")
    fill_in I18n.t("trades.form.holding"), with: "AAPL"
    # "Date": ver comentario no teste de compra acima.
    fill_in "Date", with: Date.current
    fill_in I18n.t("trades.form.qty"), with: qty
    fill_in "model[price]", with: 215.33

    submit_trade_form

    visit_trades

    within_trades do
      # Nome em ingles vindo de Trade.build_name -- ver reporte.
      assert_text "Sell #{qty}.0 shares of AAPL"
    end
  end

  private
    # O link fica na aba de posicoes (holdings/index), nao no header da conta --
    # por isso a chave e holdings.index.new_holding e nao accounts.show.activity.
    def open_new_trade_modal
      click_on I18n.t("holdings.index.new_holding")
    end

    # O submit e assincrono: o POST /trades responde com um turbo_stream de
    # redirect_back, e o Turbo so navega quando essa resposta chega. Sem esperar,
    # o `visit_trades` seguinte corre junto com o POST (a lista chega a ser
    # renderizada antes do INSERT) e depois o redirect atrasado ainda arrasta o
    # navegador de volta para a aba anterior. Esperar o modal fechar sincroniza
    # com o fim do redirect.
    def submit_trade_form
      click_button I18n.t("trades.form.submit")
      assert_no_selector "#modal dialog"
    end

    def within_trades(&block)
      within "#" + dom_id(@account, "entries"), &block
    end

    def visit_trades
      visit account_path(@account, tab: "activity")
    end

    def visit_account_portfolio
      visit account_path(@account, tab: "holdings")
    end
end
