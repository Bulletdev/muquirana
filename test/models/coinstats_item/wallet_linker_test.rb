require "test_helper"
require "webmock/minitest"

class CoinstatsItem::WalletLinkerTest < ActiveSupport::TestCase
  BASE = Provider::Coinstats::BASE_URL

  setup do
    @family = families(:dylan_family)
    @item = @family.coinstats_items.create!(name: "CoinStats", api_key: "key-123")
    @address = "0x123abc"
    @blockchain = "ethereum"
  end

  def stub_balances(tokens)
    body = [ { "blockchain" => @blockchain, "address" => @address, "connectionId" => @blockchain, "balances" => tokens } ].to_json
    stub_request(:get, "#{BASE}/wallet/balances")
      .with(query: { "wallets" => "#{@blockchain}:#{@address}" })
      .to_return(status: 200, body: body, headers: { "Content-Type" => "application/json" })
  end

  def stub_defi(protocols)
    stub_request(:get, "#{BASE}/wallet/defi")
      .with(query: { "address" => @address, "connectionId" => @blockchain })
      .to_return(status: 200, body: { "protocols" => protocols }.to_json, headers: { "Content-Type" => "application/json" })
  end

  test "creates exactly ONE aggregated account per wallet (tokens + DeFi)" do
    stub_balances([
      { "coinId" => "ethereum", "symbol" => "ETH", "name" => "Ethereum", "amount" => 1.5, "price" => 2000 },
      { "coinId" => "dai", "symbol" => "DAI", "name" => "Dai", "amount" => 1000, "price" => 1 }
    ])
    stub_defi([
      { "id" => "aave", "name" => "Aave",
        "investments" => [ { "name" => "lending", "assets" => [ { "coinId" => "usdc", "symbol" => "USDC", "amount" => 500, "price" => { "USD" => 500 }, "title" => "supplied" } ] } ] }
    ])

    result = nil
    assert_difference [ "Account.count", "CoinstatsAccount.count", "AccountProvider.count" ], 1 do
      result = @item.link_wallet!(address: @address, blockchain: @blockchain)
    end

    assert result.success?

    coinstats_account = @item.coinstats_accounts.sole
    # 1.5*2000 + 1000*1 + 500 (DeFi) = 4500 USD
    assert_equal 4500.0, coinstats_account.current_balance.to_f
    assert_equal "USD", coinstats_account.currency
    assert_equal "wallet:ethereum:0x123abc", coinstats_account.account_id
    assert_equal "0x123abc", coinstats_account.wallet_address
    assert_equal "ethereum", coinstats_account.blockchain

    account = coinstats_account.account
    assert_equal "Crypto", account.accountable_type
    assert_equal 2, coinstats_account.raw_payload["tokens"].size
    assert_equal 1, coinstats_account.raw_payload["defi_positions"].size
  end

  test "account_id encodes the chain so the same address on two chains yields two accounts" do
    stub_balances([ { "coinId" => "ethereum", "symbol" => "ETH", "amount" => 1, "price" => 2000 } ])
    stub_defi([])

    @item.link_wallet!(address: @address, blockchain: "ethereum")

    @blockchain = "polygon"
    stub_request(:get, "#{BASE}/wallet/balances")
      .with(query: { "wallets" => "polygon:#{@address}" })
      .to_return(status: 200, body: [ { "blockchain" => "polygon", "address" => @address, "connectionId" => "polygon", "balances" => [ { "coinId" => "matic", "symbol" => "MATIC", "amount" => 10, "price" => 1 } ] } ].to_json, headers: { "Content-Type" => "application/json" })
    stub_request(:get, "#{BASE}/wallet/defi")
      .with(query: { "address" => @address, "connectionId" => "polygon" })
      .to_return(status: 200, body: { "protocols" => [] }.to_json, headers: { "Content-Type" => "application/json" })

    assert_difference "CoinstatsAccount.count", 1 do
      @item.link_wallet!(address: @address, blockchain: "polygon")
    end

    assert_equal 2, @item.coinstats_accounts.count
    assert_equal %w[wallet:ethereum:0x123abc wallet:polygon:0x123abc].sort,
                 @item.coinstats_accounts.pluck(:account_id).sort
  end

  test "returns failure when wallet has no tokens and no DeFi" do
    stub_balances([])
    stub_defi([])

    result = nil
    assert_no_difference [ "Account.count", "CoinstatsAccount.count" ] do
      result = @item.link_wallet!(address: @address, blockchain: @blockchain)
    end

    refute result.success?
    assert_includes result.errors.join, "Nenhum token"
  end
end
