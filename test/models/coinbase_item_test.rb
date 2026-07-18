require "test_helper"
require "webmock/minitest"

class CoinbaseItemTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
    # Chave EC real para o JWT poder ser assinado nas chamadas autenticadas.
    @private_key_pem = OpenSSL::PKey::EC.generate("prime256v1").to_pem
    @item = @family.coinbase_items.create!(
      name: "Coinbase",
      api_key: "organizations/org/apiKeys/key",
      api_secret: @private_key_pem
    )
    # Taxa USD -> moeda da familia (BRL) semeada para nao tocar a rede.
    ExchangeRate.create!(from_currency: "USD", to_currency: @family.currency, date: Date.current, rate: 5)
  end

  def stub_accounts(accounts)
    stub_request(:get, "https://api.coinbase.com/v2/accounts")
      .to_return(
        status: 200,
        body: { "data" => accounts, "pagination" => { "next_uri" => nil } }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
  end

  test "credentials are encrypted at rest" do
    raw = ActiveRecord::Base.connection.select_value(
      "SELECT api_secret FROM coinbase_items WHERE id = '#{@item.id}'"
    )
    assert_not_equal @private_key_pem, raw
    assert_equal @private_key_pem, @item.reload.api_secret
  end

  test "sets Coinbase institution defaults on create" do
    assert_equal "Coinbase", @item.institution_name
    assert_equal "coinbase.com", @item.institution_domain
  end

  test "credentials_configured? reflects presence" do
    assert @item.credentials_configured?
  end

  test "successful sync creates a crypto account with BRL holdings converted from native currency" do
    stub_accounts([
      {
        "id" => "wallet-btc",
        "name" => "BTC Wallet",
        "type" => "wallet",
        "currency" => { "code" => "BTC", "name" => "Bitcoin", "type" => "crypto" },
        "balance" => { "amount" => "0.5", "currency" => "BTC" },
        "native_balance" => { "amount" => "20000.00", "currency" => "USD" }
      }
    ])

    @item.import_latest_coinbase_data
    @item.process_accounts

    coinbase_account = @item.coinbase_accounts.sole
    assert_equal "combined", coinbase_account.account_type
    assert_equal "USD", coinbase_account.native_currency

    account = coinbase_account.reload.account
    assert account.present?, "expected an Account linked via AccountProvider"
    assert account.crypto?
    assert_equal @family.currency, account.currency

    holding = account.holdings.sole
    assert_equal "CRYPTO:BTC", holding.security.ticker
    assert_equal 0.5.to_d, holding.qty
    assert_equal @family.currency, holding.currency
    # 20000 USD * 5 (USD->BRL) = 100000
    assert_equal 100_000, holding.amount
    # Saldo da conta reflete a soma dos holdings em BRL
    assert_equal 100_000, account.balance
    assert AccountProvider.exists?(provider_type: "CoinbaseAccount", provider_id: coinbase_account.id)
  end

  test "creates one holding per crypto wallet and skips fiat and zero-balance wallets" do
    stub_accounts([
      {
        "id" => "w-btc",
        "currency" => { "code" => "BTC", "name" => "Bitcoin", "type" => "crypto" },
        "balance" => { "amount" => "1", "currency" => "BTC" },
        "native_balance" => { "amount" => "40000.00", "currency" => "USD" }
      },
      {
        "id" => "w-eth",
        "currency" => { "code" => "ETH", "name" => "Ethereum", "type" => "crypto" },
        "balance" => { "amount" => "2", "currency" => "ETH" },
        "native_balance" => { "amount" => "6000.00", "currency" => "USD" }
      },
      {
        "id" => "w-usd",
        "currency" => { "code" => "USD", "name" => "US Dollar", "type" => "fiat" },
        "balance" => { "amount" => "100", "currency" => "USD" },
        "native_balance" => { "amount" => "100.00", "currency" => "USD" }
      },
      {
        "id" => "w-empty",
        "currency" => { "code" => "SOL", "name" => "Solana", "type" => "crypto" },
        "balance" => { "amount" => "0", "currency" => "SOL" },
        "native_balance" => { "amount" => "0.00", "currency" => "USD" }
      }
    ])

    @item.import_latest_coinbase_data
    @item.process_accounts

    account = @item.coinbase_accounts.sole.reload.account
    tickers = account.holdings.map { |h| h.security.ticker }.sort
    assert_equal %w[CRYPTO:BTC CRYPTO:ETH], tickers
    # (40000 + 6000) USD * 5 = 230000 BRL
    assert_equal 230_000, account.balance
  end

  test "invalid key surfaces an actionable pt-BR error and leaves item recoverable" do
    stub_request(:get, "https://api.coinbase.com/v2/accounts")
      .to_return(status: 401, body: { "errors" => [ { "message" => "invalid signature" } ] }.to_json)

    sync = @item.syncs.create!

    assert_raises(Provider::Coinbase::Error) do
      CoinbaseItem::Syncer.new(@item).perform_sync(sync)
    end

    @item.reload
    assert @item.requires_update?, "item should be in a recoverable state, not broken"
    assert_match(/rejeitad|chave/i, @item.last_error)
  end

  test "permission error maps to actionable pt-BR message" do
    stub_request(:get, "https://api.coinbase.com/v2/accounts")
      .to_return(status: 403, body: { "errors" => [ { "message" => "missing scope" } ] }.to_json)

    sync = @item.syncs.create!

    assert_raises(Provider::Coinbase::Error) do
      CoinbaseItem::Syncer.new(@item).perform_sync(sync)
    end

    assert @item.reload.requires_update?
    assert_match(/permiss[aã]o/i, @item.last_error)
  end

  test "missing credentials fail the sync with a clear message" do
    @item.update_columns(api_key: nil, api_secret: nil)
    sync = @item.syncs.create!

    assert_raises(Provider::Coinbase::Error) do
      CoinbaseItem::Syncer.new(@item).perform_sync(sync)
    end

    assert_match(/credenciais/i, @item.reload.last_error)
  end

  test "a later successful sync clears the requires_update state" do
    @item.update!(status: :requires_update, last_error: "erro antigo")
    stub_accounts([
      {
        "id" => "w-btc",
        "currency" => { "code" => "BTC", "name" => "Bitcoin", "type" => "crypto" },
        "balance" => { "amount" => "0.1", "currency" => "BTC" },
        "native_balance" => { "amount" => "4000.00", "currency" => "USD" }
      }
    ])

    sync = @item.syncs.create!
    CoinbaseItem::Syncer.new(@item).perform_sync(sync)

    @item.reload
    assert @item.good?
    assert_nil @item.last_error
  end
end
