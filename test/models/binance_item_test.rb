require "test_helper"
require "webmock/minitest"

class BinanceItemTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
    @item = @family.binance_items.create!(
      name: "Binance",
      api_key: "key-123",
      api_secret: "secret-123"
    )
    # Taxa USD -> moeda da familia (BRL) semeada para nao tocar a rede.
    ExchangeRate.create!(from_currency: "USD", to_currency: @family.currency, date: Date.current, rate: 5)

    # Carteiras adicionais vazias por padrao; testes especificos sobrescrevem.
    stub_funding([])
    stub_earn_flexible([])
    stub_earn_locked([])
  end

  test "credentials are encrypted at rest" do
    raw = ActiveRecord::Base.connection.select_value(
      "SELECT api_secret FROM binance_items WHERE id = '#{@item.id}'"
    )
    assert_not_equal "secret-123", raw
    assert_equal "secret-123", @item.reload.api_secret
  end

  test "sets Binance institution defaults on create" do
    assert_equal "Binance", @item.institution_name
    assert_equal "binance.com", @item.institution_domain
  end

  test "credentials_configured? reflects presence" do
    assert @item.credentials_configured?
  end

  def stub_spot_account(balances)
    stub_request(:get, /binance\.com\/api\/v3\/account/)
      .to_return(status: 200, body: { "balances" => balances }.to_json)
  end

  def stub_funding(assets)
    stub_request(:post, %r{binance\.com/sapi/v1/asset/get-funding-asset})
      .to_return(status: 200, body: assets.to_json, headers: { "Content-Type" => "application/json" })
  end

  def stub_earn_flexible(rows)
    stub_request(:get, %r{binance\.com/sapi/v1/simple-earn/flexible/position})
      .to_return(status: 200, body: { "rows" => rows, "total" => rows.size }.to_json)
  end

  def stub_earn_locked(rows)
    stub_request(:get, %r{binance\.com/sapi/v1/simple-earn/locked/position})
      .to_return(status: 200, body: { "rows" => rows, "total" => rows.size }.to_json)
  end

  def stub_price(symbol, price)
    stub_request(:get, /binance\.com\/api\/v3\/ticker\/price.*symbol=#{symbol}/)
      .to_return(status: 200, body: { "symbol" => symbol, "price" => price }.to_json)
  end

  test "successful sync creates a crypto account with balance converted to family currency" do
    stub_spot_account([
      { "asset" => "USDT", "free" => "200.0", "locked" => "0.0" }
    ])

    @item.import_latest_binance_data
    @item.process_accounts

    binance_account = @item.binance_accounts.sole
    assert_equal 200, binance_account.current_balance
    assert_equal "USD", binance_account.currency

    account = binance_account.reload.account
    assert account.present?, "expected an Account linked via AccountProvider"
    assert account.crypto?
    assert_equal @family.currency, account.currency
    # 200 USD * 5 (USD->BRL) = 1000
    assert_equal 1000, account.balance
    assert AccountProvider.exists?(provider_type: "BinanceAccount", provider_id: binance_account.id)
  end

  test "sums non-stablecoin holdings using spot prices" do
    stub_spot_account([
      { "asset" => "BTC", "free" => "0.5", "locked" => "0.0" },
      { "asset" => "USDT", "free" => "100.0", "locked" => "0.0" }
    ])
    stub_price("BTCUSDT", "60000.00")

    @item.import_latest_binance_data

    # 0.5 BTC * 60000 + 100 USDT = 30100 USD
    assert_equal 30100, @item.binance_accounts.sole.current_balance
  end

  test "aggregates spot, funding and earn balances of the same asset" do
    stub_spot_account([ { "asset" => "USDT", "free" => "10.0", "locked" => "0.0" } ])
    stub_funding([ { "asset" => "USDT", "free" => "5.0", "locked" => "0.0", "freeze" => "0.0", "withdrawing" => "0.0" } ])
    stub_earn_flexible([ { "asset" => "USDT", "totalAmount" => "3.0" } ])
    stub_earn_locked([ { "asset" => "USDT", "amount" => "2.0" } ])

    @item.import_latest_binance_data

    # 10 (spot) + 5 (funding) + 3 (earn flex) + 2 (earn locked) = 20 USDT
    assert_equal 20, @item.binance_accounts.sole.current_balance
  end

  test "a wallet without permission is skipped without breaking the spot sync" do
    stub_spot_account([ { "asset" => "USDT", "free" => "10.0", "locked" => "0.0" } ])
    stub_request(:post, %r{binance\.com/sapi/v1/asset/get-funding-asset})
      .to_return(status: 401, body: { "code" => -2015, "msg" => "no permission" }.to_json)

    @item.import_latest_binance_data

    # Funding foi ignorado (best-effort); o saldo Spot segue valido.
    assert_equal 10, @item.binance_accounts.sole.current_balance
  end

  test "geo restriction surfaces an actionable pt-BR error and leaves item recoverable" do
    stub_request(:get, /binance\.com\/api\/v3\/account/)
      .to_return(status: 451, body: { "msg" => "Service unavailable from a restricted location." }.to_json)

    sync = @item.syncs.create!

    assert_raises(Provider::Binance::Error) do
      BinanceItem::Syncer.new(@item).perform_sync(sync)
    end

    @item.reload
    assert @item.requires_update?, "item should be in a recoverable state, not broken"
    assert_match(/regi[aã]o|regula/i, @item.last_error)
  end

  test "permission error maps to actionable message" do
    stub_request(:get, /binance\.com\/api\/v3\/account/)
      .to_return(status: 401, body: { "code" => -2015, "msg" => "Invalid API-key, IP, or permissions for action." }.to_json)

    sync = @item.syncs.create!

    assert_raises(Provider::Binance::Error) do
      BinanceItem::Syncer.new(@item).perform_sync(sync)
    end

    assert @item.reload.requires_update?
    assert_match(/permiss[aã]o|IP/i, @item.last_error)
  end

  test "missing credentials fail the sync with a clear message" do
    @item.update_columns(api_key: nil, api_secret: nil)
    sync = @item.syncs.create!

    assert_raises(Provider::Binance::Error) do
      BinanceItem::Syncer.new(@item).perform_sync(sync)
    end

    assert_match(/credenciais/i, @item.reload.last_error)
  end

  test "a later successful sync clears the requires_update state" do
    @item.update!(status: :requires_update, last_error: "erro antigo")
    stub_spot_account([ { "asset" => "USDT", "free" => "10.0", "locked" => "0.0" } ])

    sync = @item.syncs.create!
    BinanceItem::Syncer.new(@item).perform_sync(sync)

    @item.reload
    assert @item.good?
    assert_nil @item.last_error
  end
end
