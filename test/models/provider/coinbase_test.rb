require "test_helper"
require "webmock/minitest"

class Provider::CoinbaseTest < ActiveSupport::TestCase
  setup do
    # Chave EC real (P-256) para o JWT ES256 poder ser assinado de verdade.
    @private_key_pem = OpenSSL::PKey::EC.generate("prime256v1").to_pem
    @coinbase = Provider::Coinbase.new(
      api_key: "organizations/org/apiKeys/key",
      api_secret: @private_key_pem,
      api_base_url: "https://api.coinbase.com"
    )
  end

  test "get_spot_price returns the data hash from the public endpoint" do
    stub_request(:get, "https://api.coinbase.com/v2/prices/BTC-BRL/spot")
      .to_return(status: 200, body: { "data" => { "amount" => "327000.00", "base" => "BTC", "currency" => "BRL" } }.to_json)

    data = @coinbase.get_spot_price("BTC-BRL")

    assert_equal "327000.00", data["amount"]
    assert_equal "BRL", data["currency"]
  end

  test "get_accounts signs the request with a Bearer JWT and returns the data array" do
    stub = stub_request(:get, "https://api.coinbase.com/v2/accounts")
      .with { |req| req.headers["Authorization"].to_s.start_with?("Bearer ") }
      .to_return(
        status: 200,
        body: {
          "data" => [ { "id" => "w1", "balance" => { "amount" => "0.5", "currency" => "BTC" } } ],
          "pagination" => { "next_uri" => nil }
        }.to_json
      )

    result = @coinbase.get_accounts

    assert_requested(stub)
    assert_equal 1, result.size
    assert_equal "w1", result.first["id"]
  end

  test "get_accounts follows pagination next_uri" do
    stub_request(:get, "https://api.coinbase.com/v2/accounts")
      .to_return(status: 200, body: {
        "data" => [ { "id" => "w1" } ],
        "pagination" => { "next_uri" => "/v2/accounts?starting_after=w1" }
      }.to_json)

    stub_request(:get, "https://api.coinbase.com/v2/accounts?starting_after=w1")
      .to_return(status: 200, body: {
        "data" => [ { "id" => "w2" } ],
        "pagination" => { "next_uri" => nil }
      }.to_json)

    result = @coinbase.get_accounts

    assert_equal %w[w1 w2], result.map { |a| a["id"] }
  end

  test "maps HTTP 401 to AuthenticationError" do
    stub_request(:get, "https://api.coinbase.com/v2/accounts")
      .to_return(status: 401, body: { "errors" => [ { "message" => "invalid signature" } ] }.to_json)

    assert_raises(Provider::Coinbase::AuthenticationError) { @coinbase.get_accounts }
  end

  test "maps HTTP 403 to PermissionError" do
    stub_request(:get, "https://api.coinbase.com/v2/accounts")
      .to_return(status: 403, body: { "errors" => [ { "message" => "missing scope" } ] }.to_json)

    assert_raises(Provider::Coinbase::PermissionError) { @coinbase.get_accounts }
  end

  test "maps HTTP 429 to RateLimitError" do
    stub_request(:get, "https://api.coinbase.com/v2/accounts")
      .to_return(status: 429, body: "")

    assert_raises(Provider::Coinbase::RateLimitError) { @coinbase.get_accounts }
  end

  test "an invalid PEM private key raises AuthenticationError (credential problem, not network)" do
    bad = Provider::Coinbase.new(api_key: "k", api_secret: "not-a-pem", api_base_url: "https://api.coinbase.com")

    assert_raises(Provider::Coinbase::AuthenticationError) { bad.get_accounts }
  end

  test "honors a custom api_base_url" do
    custom = Provider::Coinbase.new(
      api_key: "organizations/org/apiKeys/key",
      api_secret: @private_key_pem,
      api_base_url: "https://api.coinbase.example"
    )

    stub = stub_request(:get, "https://api.coinbase.example/v2/accounts")
      .to_return(status: 200, body: { "data" => [], "pagination" => { "next_uri" => nil } }.to_json)

    custom.get_accounts

    assert_requested(stub)
  end
end
