require "test_helper"
require "webmock/minitest"

class CoinstatsItem::DefiAccountManagerTest < ActiveSupport::TestCase
  BASE = Provider::Coinstats::BASE_URL

  setup do
    @family = families(:dylan_family)
    @item = @family.coinstats_items.create!(name: "CoinStats", api_key: "key-123")
    @provider = @item.coinstats_provider
    @provider.stubs(:min_request_interval).returns(0)
  end

  test "aggregates DeFi position values across protocols and investments" do
    protocols = [
      { "id" => "aave", "name" => "Aave",
        "investments" => [ { "name" => "lending", "assets" => [
          { "coinId" => "usdc", "symbol" => "USDC", "amount" => 100, "price" => { "USD" => 100 }, "title" => "supplied" },
          { "coinId" => "usdc", "symbol" => "USDC", "amount" => 5, "price" => { "USD" => 5 }, "title" => "reward" }
        ] } ] },
      { "id" => "lido", "name" => "Lido",
        "investments" => [ { "name" => "staking", "assets" => [
          { "coinId" => "steth", "symbol" => "stETH", "amount" => 1, "price" => { "USD" => 2000 }, "title" => "deposit" }
        ] } ] }
    ]

    stub_request(:get, "#{BASE}/wallet/defi")
      .with(query: { "address" => "0xabc", "connectionId" => "ethereum" })
      .to_return(status: 200, body: { "protocols" => protocols }.to_json, headers: { "Content-Type" => "application/json" })

    result = CoinstatsItem::DefiAccountManager.new(@item, provider: @provider)
      .wallet_defi_value(address: "0xabc", blockchain: "ethereum")

    assert_equal 2105.0, result.total_usd.to_f # 100 + 5 + 2000
    assert_equal 3, result.positions.size
    # account_id codifica a chain
    assert result.positions.all? { |p| p["account_id"].start_with?("defi:ethereum:") }
  end

  test "skips zero-amount assets" do
    protocols = [
      { "id" => "aave", "name" => "Aave",
        "investments" => [ { "name" => "lending", "assets" => [
          { "coinId" => "usdc", "symbol" => "USDC", "amount" => 0, "price" => { "USD" => 0 }, "title" => "supplied" }
        ] } ] }
    ]

    stub_request(:get, "#{BASE}/wallet/defi")
      .with(query: { "address" => "0xabc", "connectionId" => "ethereum" })
      .to_return(status: 200, body: { "protocols" => protocols }.to_json, headers: { "Content-Type" => "application/json" })

    result = CoinstatsItem::DefiAccountManager.new(@item, provider: @provider)
      .wallet_defi_value(address: "0xabc", blockchain: "ethereum")

    assert_equal 0.0, result.total_usd.to_f
    assert_empty result.positions
  end
end
