require "test_helper"
require "webmock/minitest"

class Provider::MercadoBitcoinTest < ActiveSupport::TestCase
  setup do
    @mb = Provider::MercadoBitcoin.new(
      api_key: "test-key",
      api_secret: "test-secret",
      base_url: "https://api.mercadobitcoin.net"
    )
  end

  def stub_authorize(status: 200, token: "tok-1", body: nil)
    body ||= { "access_token" => token, "expiration" => 9_999_999_999 }.to_json
    stub_request(:post, %r{api\.mercadobitcoin\.net/api/v4/authorize})
      .to_return(status: status, body: body, headers: { "Content-Type" => "application/json" })
  end

  def stub_accounts(status: 200, body: [ { "id" => "acc-1" } ].to_json)
    stub_request(:get, %r{api\.mercadobitcoin\.net/api/v4/accounts\z})
      .to_return(status: status, body: body, headers: { "Content-Type" => "application/json" })
  end

  def stub_balances(entries, account_id: "acc-1")
    stub_request(:get, %r{api\.mercadobitcoin\.net/api/v4/accounts/#{account_id}/balances})
      .to_return(status: 200, body: entries.to_json, headers: { "Content-Type" => "application/json" })
  end

  test "get_account_info authorizes, resolves the account and keys balances by symbol" do
    stub_authorize
    stub_accounts
    stub_balances([
      { "symbol" => "BRL", "available" => "1500.0", "total" => "1500.0" },
      { "symbol" => "BTC", "available" => "0.5", "total" => "0.5" }
    ])

    result = @mb.get_account_info

    assert_equal "1500.0", result["balance"]["brl"]["available"]
    assert_equal "0.5", result["balance"]["btc"]["total"]
  end

  test "authorize sends login and password" do
    auth = stub_request(:post, %r{/api/v4/authorize})
      .with(body: hash_including("login" => "test-key", "password" => "test-secret"))
      .to_return(status: 200, body: { "access_token" => "tok" }.to_json)
    stub_accounts
    stub_balances([])

    @mb.get_account_info

    assert_requested(auth)
  end

  test "reads balances with the bearer token from authorize" do
    stub_authorize(token: "bear-123")
    stub_accounts
    bal = stub_request(:get, %r{/api/v4/accounts/acc-1/balances})
      .with(headers: { "Authorization" => "Bearer bear-123" })
      .to_return(status: 200, body: [].to_json)

    @mb.get_account_info

    assert_requested(bal)
  end

  test "bad credentials on authorize raise AuthenticationError" do
    stub_authorize(status: 401, body: { "message" => "Chave invalida" }.to_json)

    assert_raises(Provider::MercadoBitcoin::AuthenticationError) { @mb.get_account_info }
  end

  test "403 reading the account raises PermissionError" do
    stub_authorize
    stub_accounts(status: 403, body: { "message" => "Sem permissao" }.to_json)

    assert_raises(Provider::MercadoBitcoin::PermissionError) { @mb.get_account_info }
  end

  test "429 raises RateLimitError" do
    stub_authorize(status: 429, body: "")

    assert_raises(Provider::MercadoBitcoin::RateLimitError) { @mb.get_account_info }
  end

  test "get_ticker_price returns the last price for the BRL pair" do
    stub_request(:get, %r{/api/v4/tickers})
      .with(query: { "symbols" => "BTC-BRL" })
      .to_return(status: 200, body: [ { "pair" => "BTC-BRL", "last" => "350000.00" } ].to_json)

    assert_equal "350000.00", @mb.get_ticker_price("BTC")
  end

  test "get_ticker_price returns nil on API error" do
    stub_request(:get, %r{/api/v4/tickers})
      .to_return(status: 400, body: { "message" => "Par invalido" }.to_json)

    assert_nil @mb.get_ticker_price("NOPE")
  end

  test "honors a custom base_url" do
    custom = Provider::MercadoBitcoin.new(api_key: "k", api_secret: "s", base_url: "https://mb.example")

    auth = stub_request(:post, %r{mb\.example/api/v4/authorize})
      .to_return(status: 200, body: { "access_token" => "t" }.to_json)
    stub_request(:get, %r{mb\.example/api/v4/accounts\z})
      .to_return(status: 200, body: [ { "id" => "x" } ].to_json)
    stub_request(:get, %r{mb\.example/api/v4/accounts/x/balances})
      .to_return(status: 200, body: [].to_json)

    custom.get_account_info

    assert_requested(auth)
  end
end
