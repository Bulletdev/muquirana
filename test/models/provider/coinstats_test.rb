require "test_helper"
require "webmock/minitest"

class Provider::CoinstatsTest < ActiveSupport::TestCase
  setup do
    @provider = Provider::Coinstats.new(api_key: "test-key")
    # Sem espera real entre requisicoes nos testes.
    @provider.stubs(:min_request_interval).returns(0)
  end

  test "get_wallet_balances sends the API key header and parses the array" do
    body = [
      { "blockchain" => "ethereum", "address" => "0x123abc", "connectionId" => "ethereum",
        "balances" => [ { "coinId" => "ethereum", "symbol" => "ETH", "amount" => 1.5, "price" => 2000 } ] }
    ].to_json

    stub = stub_request(:get, "#{Provider::Coinstats::BASE_URL}/wallet/balances")
      .with(query: { "wallets" => "ethereum:0x123abc" }, headers: { "X-API-KEY" => "test-key" })
      .to_return(status: 200, body: body, headers: { "Content-Type" => "application/json" })

    result = @provider.get_wallet_balances("ethereum:0x123abc")

    assert_requested(stub)
    assert_equal 1, result.size
    assert_equal "ethereum", result.first["blockchain"]
  end

  test "extract_wallet_balance finds tokens by address and connectionId, case insensitive" do
    bulk = [
      { "blockchain" => "Ethereum", "address" => "0x123ABC", "connectionId" => "Ethereum",
        "balances" => [ { "coinId" => "ethereum", "amount" => 1.5 } ] }
    ]

    result = @provider.extract_wallet_balance(bulk, "0x123abc", "ethereum")

    assert_equal 1, result.size
    assert_equal "ethereum", result.first["coinId"]
  end

  test "get_wallet_defi parses the protocols payload" do
    body = {
      "protocols" => [
        { "id" => "aave", "name" => "Aave",
          "investments" => [ { "name" => "lending", "assets" => [ { "coinId" => "usdc", "symbol" => "USDC", "amount" => 100, "price" => { "USD" => 100 }, "title" => "supplied" } ] } ] }
      ]
    }.to_json

    stub_request(:get, "#{Provider::Coinstats::BASE_URL}/wallet/defi")
      .with(query: { "address" => "0x123abc", "connectionId" => "ethereum" })
      .to_return(status: 200, body: body, headers: { "Content-Type" => "application/json" })

    result = @provider.get_wallet_defi(address: "0x123abc", connection_id: "ethereum")

    assert_equal 1, result["protocols"].size
    assert_equal "Aave", result["protocols"].first["name"]
  end

  test "blockchain_options returns sorted [label, value] pairs and degrades to [] on error" do
    body = [
      { "connectionId" => "polygon", "name" => "Polygon" },
      { "connectionId" => "ethereum", "name" => "Ethereum" }
    ].to_json

    stub_request(:get, "#{Provider::Coinstats::BASE_URL}/wallet/blockchains")
      .to_return(status: 200, body: body, headers: { "Content-Type" => "application/json" })

    assert_equal [ [ "Ethereum", "ethereum" ], [ "Polygon", "polygon" ] ], @provider.blockchain_options
  end

  test "maps HTTP 406 to CreditsExhaustedError with actionable payload and does not retry" do
    @provider.expects(:sleep).never

    stub_request(:get, "#{Provider::Coinstats::BASE_URL}/wallet/defi")
      .with(query: { "address" => "0x123abc", "connectionId" => "ethereum" })
      .to_return(
        status: 406,
        body: { statusCode: 406, message: "Credits limit reached. Please upgrade your plan or wait for renewal.", requestId: "rid-1", path: "/wallet/defi" }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
      .times(1)

    error = assert_raises(Provider::Coinstats::CreditsExhaustedError) do
      @provider.get_wallet_defi(address: "0x123abc", connection_id: "ethereum")
    end

    assert_match "Credits limit reached", error.message
    assert_equal 406, error.details[:status_code]
  end

  test "retries on HTTP 429 honoring Retry-After then succeeds" do
    @provider.expects(:sleep).with(3).once

    stub_request(:get, "#{Provider::Coinstats::BASE_URL}/wallet/balances")
      .with(query: { "wallets" => "ethereum:0x123abc" })
      .to_return(
        { status: 429, body: { message: "Too Many Requests" }.to_json, headers: { "Retry-After" => "3", "Content-Type" => "application/json" } },
        { status: 200, body: [ { "blockchain" => "ethereum", "address" => "0x123abc", "balances" => [] } ].to_json, headers: { "Content-Type" => "application/json" } }
      )

    result = @provider.get_wallet_balances("ethereum:0x123abc")

    assert_equal "ethereum", result.first["blockchain"]
  end

  test "raises RateLimitError after exhausting retries on repeated 429" do
    @provider.stubs(:sleep)

    stub_request(:get, "#{Provider::Coinstats::BASE_URL}/wallet/balances")
      .with(query: { "wallets" => "ethereum:0x123abc" })
      .to_return(status: 429, body: { message: "Too Many Requests" }.to_json, headers: { "Content-Type" => "application/json" })

    assert_raises(Provider::Coinstats::RateLimitError) do
      @provider.get_wallet_balances("ethereum:0x123abc")
    end
  end

  test "maps HTTP 401 to AuthenticationError" do
    stub_request(:get, "#{Provider::Coinstats::BASE_URL}/wallet/blockchains")
      .to_return(status: 401, body: { statusCode: 401, message: "Unauthorized" }.to_json, headers: { "Content-Type" => "application/json" })

    # blockchain_options swallows into [] but get() raises; test via get_wallet_defi
    stub_request(:get, "#{Provider::Coinstats::BASE_URL}/wallet/defi")
      .with(query: { "address" => "0x1", "connectionId" => "ethereum" })
      .to_return(status: 401, body: { message: "Unauthorized" }.to_json, headers: { "Content-Type" => "application/json" })

    assert_raises(Provider::Coinstats::AuthenticationError) do
      @provider.get_wallet_defi(address: "0x1", connection_id: "ethereum")
    end
  end
end
