require "test_helper"
require "webmock/minitest"

class IbkrItemTest < ActiveSupport::TestCase
  BASE = "https://gdcdyn.interactivebrokers.com".freeze

  setup do
    @family = families(:dylan_family)
    assert_equal "BRL", @family.currency, "o teste assume familia em BRL"

    @item = @family.ibkr_items.create!(name: "IBKR", query_id: "123456", token: "TOKEN")
    @statement_xml = file_fixture("ibkr/flex_statement.xml").read

    # Taxas semeadas (sem tocar a rede) para todas as datas usadas no fixture:
    # posicoes/caixa em 2026-06-30; trades em 2026-06-10 (USD) e 2026-06-12 (GBP).
    [ Date.new(2026, 6, 30), Date.new(2026, 6, 10), Date.new(2026, 6, 12) ].each do |d|
      ExchangeRate.find_or_create_by!(from_currency: "USD", to_currency: "BRL", date: d, rate: 5)
      ExchangeRate.find_or_create_by!(from_currency: "GBP", to_currency: "BRL", date: d, rate: 6)
    end
  end

  test "credentials are encrypted at rest" do
    raw = ActiveRecord::Base.connection.select_value("SELECT token FROM ibkr_items WHERE id = '#{@item.id}'")
    assert_not_equal "TOKEN", raw
    assert_equal "TOKEN", @item.reload.token
  end

  test "sets Interactive Brokers institution defaults on create" do
    assert_equal "Interactive Brokers", @item.institution_name
    assert_equal "interactivebrokers.com", @item.institution_domain
  end

  test "imports the Flex statement and materializes multi-currency holdings converted to BRL" do
    stub_flex_flow

    @item.import_latest_ibkr_data
    @item.process_accounts

    ibkr_account = @item.ibkr_accounts.sole
    assert_equal "U1234567", ibkr_account.ibkr_account_id
    assert_equal "USD", ibkr_account.currency

    account = ibkr_account.reload.account
    assert account.present?, "esperava uma Account ligada via AccountProvider"
    assert_equal "Investment", account.accountable_type
    assert_equal "BRL", account.currency
    assert AccountProvider.exists?(provider_type: "IbkrAccount", provider_id: ibkr_account.id)

    holdings = account.holdings.index_by { |h| h.security.ticker }
    assert_equal 2, holdings.size

    # AAPL: 10 @ 190 USD -> 950 BRL/cota, valor 9500 BRL
    assert_equal "BRL", holdings["AAPL"].currency
    assert_equal 950, holdings["AAPL"].price
    assert_equal 9500, holdings["AAPL"].amount
    # VOD: 100 @ 0.80 GBP -> 4.80 BRL/cota, valor 480 BRL
    assert_equal 4.8, holdings["VOD"].price.to_f
    assert_equal 480, holdings["VOD"].amount

    # Saldo = holdings (9980) + caixa (500 USD -> 2500 BRL) = 12480 BRL
    assert_equal 12_480, account.reload.balance
  end

  test "materializes trades converted to BRL" do
    stub_flex_flow

    @item.import_latest_ibkr_data
    @item.process_accounts

    account = @item.ibkr_accounts.sole.reload.account
    trades = account.entries.where(entryable_type: "Trade").includes(:entryable).index_by { |e| e.entryable.security.ticker }
    assert_equal 2, trades.size

    # AAPL BUY 10 @ 150 USD -> preco 750 BRL, valor 7500 BRL (compra = positivo)
    aapl = trades["AAPL"]
    assert_equal "BRL", aapl.currency
    assert_equal 10, aapl.entryable.qty
    assert_equal 750, aapl.entryable.price
    assert_equal 7500, aapl.amount
    assert_equal "ibkr", aapl.source

    # VOD BUY 100 @ 0.75 GBP -> preco 4.50 BRL, valor 450 BRL
    vod = trades["VOD"]
    assert_equal 4.5, vod.entryable.price.to_f
    assert_equal 450, vod.amount
  end

  test "re-importing is idempotent (no duplicate holdings or trades)" do
    stub_flex_flow

    @item.import_latest_ibkr_data
    @item.process_accounts
    @item.import_latest_ibkr_data
    @item.process_accounts

    account = @item.ibkr_accounts.sole.reload.account
    assert_equal 2, account.holdings.count
    assert_equal 2, account.entries.where(entryable_type: "Trade").count
  end

  test "invalid token surfaces an actionable pt-BR error and leaves item recoverable" do
    stub_send_request(fail_response("1020", "Invalid request or unable to validate request."))

    sync = @item.syncs.create!
    assert_raises(Provider::IbkrFlex::Error) do
      IbkrItem::Syncer.new(@item).perform_sync(sync)
    end

    @item.reload
    assert @item.requires_update?, "item deveria ficar recuperavel, nao quebrado"
    assert_match(/Query ID|Token/i, @item.last_error)
  end

  test "statement still generating surfaces an actionable retry message" do
    provider = Provider::IbkrFlex.new(query_id: "123456", token: "TOKEN", base_url: BASE)
    provider.stubs(:download_statement).raises(Provider::IbkrFlex::StatementNotReadyError.new("pending"))
    @item.stubs(:ibkr_provider).returns(provider)

    sync = @item.syncs.create!
    assert_raises(Provider::IbkrFlex::Error) do
      IbkrItem::Syncer.new(@item).perform_sync(sync)
    end

    assert @item.reload.requires_update?
    assert_match(/tempor[aá]rio|instantes|aguarde/i, @item.last_error)
  end

  test "missing credentials fail the sync with a clear message" do
    @item.update_columns(query_id: nil, token: nil)
    sync = @item.syncs.create!

    assert_raises(Provider::IbkrFlex::Error) do
      IbkrItem::Syncer.new(@item).perform_sync(sync)
    end

    assert_match(/credenciais/i, @item.reload.last_error)
  end

  test "a later successful sync clears the requires_update state" do
    @item.update!(status: :requires_update, last_error: "erro antigo")
    stub_flex_flow

    sync = @item.syncs.create!
    IbkrItem::Syncer.new(@item).perform_sync(sync)

    @item.reload
    assert @item.good?
    assert_nil @item.last_error
  end

  private
    def stub_flex_flow
      stub_send_request(success_reference("REF999"))
      stub_request(:get, /FlexStatementService\.GetStatement/).to_return(status: 200, body: @statement_xml)
    end

    def stub_send_request(body)
      stub_request(:get, /FlexStatementService\.SendRequest/).to_return(status: 200, body: body)
    end

    def success_reference(code)
      "<FlexStatementResponse><Status>Success</Status><ReferenceCode>#{code}</ReferenceCode>" \
        "<Url>#{BASE}/Universal/servlet/FlexStatementService.GetStatement</Url></FlexStatementResponse>"
    end

    def fail_response(code, message)
      "<FlexStatementResponse><Status>Fail</Status><ErrorCode>#{code}</ErrorCode>" \
        "<ErrorMessage>#{message}</ErrorMessage></FlexStatementResponse>"
    end
end
