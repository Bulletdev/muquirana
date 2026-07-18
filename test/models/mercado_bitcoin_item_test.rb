require "test_helper"
require "webmock/minitest"

class MercadoBitcoinItemTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
    @item = @family.mercado_bitcoin_items.create!(
      name: "Mercado Bitcoin",
      api_key: "key-123",
      api_secret: "secret-123"
    )
  end

  test "credentials are encrypted at rest" do
    raw = ActiveRecord::Base.connection.select_value(
      "SELECT api_secret FROM mercado_bitcoin_items WHERE id = '#{@item.id}'"
    )
    assert_not_equal "secret-123", raw
    assert_equal "secret-123", @item.reload.api_secret
  end

  test "sets Mercado Bitcoin institution defaults on create" do
    assert_equal "Mercado Bitcoin", @item.institution_name
    assert_equal "mercadobitcoin.com.br", @item.institution_domain
  end

  test "credentials_configured? reflects presence" do
    assert @item.credentials_configured?
  end

  # --- Helpers de stub da API v4 (authorize -> accounts -> balances) ----------
  ACCOUNT_ID = "acc-1".freeze

  def stub_authorize(token: "tok-abc")
    stub_request(:post, %r{mercadobitcoin\.net/api/v4/authorize})
      .to_return(status: 200, body: { "access_token" => token, "expiration" => 9_999_999_999 }.to_json,
                 headers: { "Content-Type" => "application/json" })
  end

  def stub_accounts(account_id: ACCOUNT_ID)
    stub_request(:get, %r{mercadobitcoin\.net/api/v4/accounts\z})
      .to_return(status: 200, body: [ { "id" => account_id, "currency" => "BRL" } ].to_json,
                 headers: { "Content-Type" => "application/json" })
  end

  # `balance` no formato historico { "brl" => {"available","total"}, ... }; aqui e
  # traduzido para o array de saldos que a v4 devolve.
  def stub_account_info(balance)
    stub_authorize
    stub_accounts

    entries = balance.map do |symbol, amounts|
      amounts = { "available" => amounts, "total" => amounts } unless amounts.is_a?(Hash)
      { "symbol" => symbol.to_s.upcase, "available" => amounts["available"], "total" => amounts["total"] || amounts["available"] }
    end

    stub_request(:get, %r{mercadobitcoin\.net/api/v4/accounts/#{ACCOUNT_ID}/balances})
      .to_return(status: 200, body: entries.to_json, headers: { "Content-Type" => "application/json" })
  end

  def stub_ticker(coin, price)
    stub_request(:get, %r{mercadobitcoin\.net/api/v4/tickers})
      .with(query: { "symbols" => "#{coin.to_s.upcase}-BRL" })
      .to_return(status: 200, body: [ { "pair" => "#{coin.to_s.upcase}-BRL", "last" => price } ].to_json,
                 headers: { "Content-Type" => "application/json" })
  end

  test "successful sync creates a crypto account with the native BRL balance (no conversion)" do
    stub_account_info(
      "brl" => { "available" => "1000.0", "total" => "1000.0" }
    )

    @item.import_latest_mercado_bitcoin_data
    @item.process_accounts

    mb_account = @item.mercado_bitcoin_accounts.sole
    assert_equal 1000, mb_account.current_balance
    assert_equal "BRL", mb_account.currency

    account = mb_account.reload.account
    assert account.present?, "expected an Account linked via AccountProvider"
    assert account.crypto?
    assert_equal "BRL", account.currency
    # Sem conversao: o saldo em BRL entra direto.
    assert_equal 1000, account.balance
    assert AccountProvider.exists?(provider_type: "MercadoBitcoinAccount", provider_id: mb_account.id)
  end

  test "values crypto holdings in BRL using the public ticker" do
    stub_account_info(
      "btc" => { "available" => "0.5", "total" => "0.5" },
      "brl" => { "available" => "100.0", "total" => "100.0" }
    )
    stub_ticker("BTC", "300000.0")

    @item.import_latest_mercado_bitcoin_data

    # 0.5 BTC * 300000 + 100 BRL = 150100 BRL
    assert_equal 150100, @item.mercado_bitcoin_accounts.sole.current_balance
  end

  test "authentication rejection surfaces an actionable pt-BR error and leaves item recoverable" do
    # Credencial recusada no authorize da v4.
    stub_request(:post, %r{mercadobitcoin\.net/api/v4/authorize})
      .to_return(status: 401, body: { "message" => "Chave ou segredo invalidos." }.to_json)

    sync = @item.syncs.create!

    assert_raises(Provider::MercadoBitcoin::Error) do
      MercadoBitcoinItem::Syncer.new(@item).perform_sync(sync)
    end

    @item.reload
    assert @item.requires_update?, "item should be in a recoverable state, not broken"
    assert_match(/chave|segredo|rejeitad/i, @item.last_error)
  end

  test "permission error maps to actionable message" do
    # Authorize passa, mas a leitura da conta e barrada por falta de permissao.
    stub_authorize
    stub_request(:get, %r{mercadobitcoin\.net/api/v4/accounts\z})
      .to_return(status: 403, body: { "message" => "Chave sem permissao." }.to_json)

    sync = @item.syncs.create!

    assert_raises(Provider::MercadoBitcoin::Error) do
      MercadoBitcoinItem::Syncer.new(@item).perform_sync(sync)
    end

    assert @item.reload.requires_update?
    assert_match(/permiss[aã]o/i, @item.last_error)
  end

  test "missing credentials fail the sync with a clear message" do
    @item.update_columns(api_key: nil, api_secret: nil)
    sync = @item.syncs.create!

    assert_raises(Provider::MercadoBitcoin::Error) do
      MercadoBitcoinItem::Syncer.new(@item).perform_sync(sync)
    end

    assert_match(/credenciais/i, @item.reload.last_error)
  end

  test "a later successful sync clears the requires_update state" do
    @item.update!(status: :requires_update, last_error: "erro antigo")
    stub_account_info("brl" => { "available" => "10.0", "total" => "10.0" })

    sync = @item.syncs.create!
    MercadoBitcoinItem::Syncer.new(@item).perform_sync(sync)

    @item.reload
    assert @item.good?
    assert_nil @item.last_error
  end
end
