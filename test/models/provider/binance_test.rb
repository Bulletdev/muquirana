require "test_helper"
require "webmock/minitest"

class Provider::BinanceTest < ActiveSupport::TestCase
  setup do
    @binance = Provider::Binance.new(
      api_key: "test-key",
      api_secret: "test-secret",
      spot_base_url: "https://api.binance.com"
    )
  end

  test "get_spot_account returns parsed balances" do
    body = {
      "balances" => [
        { "asset" => "BTC", "free" => "0.5", "locked" => "0.0" },
        { "asset" => "USDT", "free" => "100.0", "locked" => "0.0" }
      ]
    }.to_json

    stub_request(:get, /api\.binance\.com\/api\/v3\/account/)
      .to_return(status: 200, body: body, headers: { "Content-Type" => "application/json" })

    result = @binance.get_spot_account

    assert_equal 2, result["balances"].size
    assert_equal "BTC", result["balances"].first["asset"]
  end

  test "sends the API key header and a signature" do
    stub = stub_request(:get, /api\.binance\.com\/api\/v3\/account/)
      .with(headers: { "X-MBX-APIKEY" => "test-key" }, query: hash_including("signature"))
      .to_return(status: 200, body: { "balances" => [] }.to_json)

    @binance.get_spot_account

    assert_requested(stub)
  end

  test "maps code -2015 (IP/permission) to PermissionError" do
    stub_request(:get, /api\.binance\.com\/api\/v3\/account/)
      .to_return(status: 401, body: { "code" => -2015, "msg" => "Invalid API-key, IP, or permissions for action." }.to_json)

    assert_raises(Provider::Binance::PermissionError) { @binance.get_spot_account }
  end

  test "maps HTTP 451 to GeoRestrictedError" do
    stub_request(:get, /api\.binance\.com\/api\/v3\/account/)
      .to_return(status: 451, body: { "msg" => "Service unavailable from a restricted location." }.to_json)

    assert_raises(Provider::Binance::GeoRestrictedError) { @binance.get_spot_account }
  end

  test "maps a restricted-location message to GeoRestrictedError even outside 451" do
    stub_request(:get, /api\.binance\.com\/api\/v3\/account/)
      .to_return(status: 400, body: { "code" => 0, "msg" => "Service unavailable from a restricted location according to eligibility." }.to_json)

    assert_raises(Provider::Binance::GeoRestrictedError) { @binance.get_spot_account }
  end

  test "maps code -2014 to AuthenticationError" do
    stub_request(:get, /api\.binance\.com\/api\/v3\/account/)
      .to_return(status: 401, body: { "code" => -2014, "msg" => "API-key format invalid." }.to_json)

    assert_raises(Provider::Binance::AuthenticationError) { @binance.get_spot_account }
  end

  test "maps HTTP 429 to RateLimitError" do
    stub_request(:get, /api\.binance\.com\/api\/v3\/account/)
      .to_return(status: 429, body: "")

    assert_raises(Provider::Binance::RateLimitError) { @binance.get_spot_account }
  end

  test "get_spot_price returns the price string" do
    stub_request(:get, /api\.binance\.com\/api\/v3\/ticker\/price/)
      .to_return(status: 200, body: { "symbol" => "BTCUSDT", "price" => "65000.00" }.to_json)

    assert_equal "65000.00", @binance.get_spot_price("BTCUSDT")
  end

  test "get_spot_price returns nil on invalid symbol" do
    stub_request(:get, /api\.binance\.com\/api\/v3\/ticker\/price/)
      .to_return(status: 400, body: { "code" => -1121, "msg" => "Invalid symbol." }.to_json)

    assert_nil @binance.get_spot_price("NOPEUSDT")
  end

  test "honors a custom spot_base_url" do
    custom = Provider::Binance.new(api_key: "k", api_secret: "s", spot_base_url: "https://api.binance.example")

    stub = stub_request(:get, /api\.binance\.example\/api\/v3\/account/)
      .to_return(status: 200, body: { "balances" => [] }.to_json)

    custom.get_spot_account

    assert_requested(stub)
  end
end
