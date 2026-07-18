require "test_helper"
require "webmock/minitest"

class CoinstatsItemsControllerTest < ActionDispatch::IntegrationTest
  BASE = Provider::Coinstats::BASE_URL

  setup do
    sign_in @user = users(:family_admin)
  end

  test "new renders the connection form" do
    get new_coinstats_item_url
    assert_response :success
  end

  test "create stores the OpenAPI key and redirects to the wallet link step" do
    assert_difference "CoinstatsItem.count", 1 do
      post coinstats_items_url, params: { coinstats_item: { name: "Minha CoinStats", api_key: "csk-123" } }
    end

    item = CoinstatsItem.order(:created_at).last
    assert_equal "Minha CoinStats", item.name
    assert_equal "csk-123", item.api_key
    assert_redirected_to link_wallet_coinstats_item_url(item)
  end

  test "create re-renders the form when the api key is missing" do
    assert_no_difference "CoinstatsItem.count" do
      post coinstats_items_url, params: { coinstats_item: { name: "X", api_key: "" } }
    end

    assert_response :unprocessable_entity
  end

  test "link_wallet GET renders the address form with a blockchain dropdown" do
    item = @user.family.coinstats_items.create!(name: "CoinStats", api_key: "csk-123")

    stub_request(:get, "#{BASE}/wallet/blockchains")
      .to_return(status: 200, body: [ { "connectionId" => "ethereum", "name" => "Ethereum" } ].to_json, headers: { "Content-Type" => "application/json" })

    get link_wallet_coinstats_item_url(item)
    assert_response :success
  end

  test "link_wallet POST links the wallet and redirects to accounts" do
    item = @user.family.coinstats_items.create!(name: "CoinStats", api_key: "csk-123")
    Provider::Coinstats.any_instance.stubs(:min_request_interval).returns(0)

    # link_wallet monta o dropdown (GET /wallet/blockchains) antes de processar o POST.
    stub_request(:get, "#{BASE}/wallet/blockchains")
      .to_return(status: 200, body: [ { "connectionId" => "ethereum", "name" => "Ethereum" } ].to_json, headers: { "Content-Type" => "application/json" })
    stub_request(:get, "#{BASE}/wallet/balances")
      .with(query: { "wallets" => "ethereum:0xabc" })
      .to_return(status: 200, body: [ { "blockchain" => "ethereum", "address" => "0xabc", "connectionId" => "ethereum", "balances" => [ { "coinId" => "ethereum", "symbol" => "ETH", "amount" => 1, "price" => 2000 } ] } ].to_json, headers: { "Content-Type" => "application/json" })
    stub_request(:get, "#{BASE}/wallet/defi")
      .with(query: { "address" => "0xabc", "connectionId" => "ethereum" })
      .to_return(status: 200, body: { "protocols" => [] }.to_json, headers: { "Content-Type" => "application/json" })
    CoinstatsItem.any_instance.stubs(:sync_later)

    assert_difference "Account.count", 1 do
      post link_wallet_coinstats_item_url(item), params: { coinstats_item: { address: "0xabc", blockchain: [ "ethereum" ] } }
    end

    assert_redirected_to accounts_url
  end

  test "link_wallet POST links several chains at once and skips the empty ones" do
    item = @user.family.coinstats_items.create!(name: "CoinStats", api_key: "csk-123")
    Provider::Coinstats.any_instance.stubs(:min_request_interval).returns(0)

    stub_request(:get, "#{BASE}/wallet/blockchains")
      .to_return(status: 200, body: [].to_json, headers: { "Content-Type" => "application/json" })
    # UMA chamada em lote para as duas chains.
    stub_request(:get, "#{BASE}/wallet/balances")
      .with(query: { "wallets" => "ethereum:0xabc,polygon:0xabc" })
      .to_return(status: 200, body: [
        { "blockchain" => "ethereum", "address" => "0xabc", "connectionId" => "ethereum", "balances" => [ { "coinId" => "ethereum", "symbol" => "ETH", "amount" => 1, "price" => 2000 } ] }
        # polygon nao retorna nada -> deve ser pulada
      ].to_json, headers: { "Content-Type" => "application/json" })
    # DeFi so e buscado para a chain que tem token (ethereum).
    stub_request(:get, "#{BASE}/wallet/defi")
      .with(query: { "address" => "0xabc", "connectionId" => "ethereum" })
      .to_return(status: 200, body: { "protocols" => [] }.to_json, headers: { "Content-Type" => "application/json" })
    CoinstatsItem.any_instance.stubs(:sync_later)

    assert_difference "Account.count", 1 do
      post link_wallet_coinstats_item_url(item), params: { coinstats_item: { address: "0xabc", blockchain: [ "ethereum", "polygon" ] } }
    end

    assert_redirected_to accounts_url
    follow_redirect!
    assert_match(/Polygon/, flash[:notice].to_s)
  end

  test "link_wallet POST offers to import anyway when no balance is found" do
    item = @user.family.coinstats_items.create!(name: "CoinStats", api_key: "csk-123")
    Provider::Coinstats.any_instance.stubs(:min_request_interval).returns(0)

    # Re-renderiza o form (busca as chains) e a chamada de saldos volta vazia.
    stub_request(:get, "#{BASE}/wallet/blockchains")
      .to_return(status: 200, body: [].to_json, headers: { "Content-Type" => "application/json" })
    stub_request(:get, "#{BASE}/wallet/balances")
      .with(query: { "wallets" => "ethereum:0xabc,polygon:0xabc" })
      .to_return(status: 200, body: [].to_json, headers: { "Content-Type" => "application/json" })

    assert_no_difference "Account.count" do
      post link_wallet_coinstats_item_url(item), params: { coinstats_item: { address: "0xabc", blockchain: [ "ethereum", "polygon" ] } }
    end

    assert_response :unprocessable_entity
    assert_match(/importar mesmo assim/i, response.body)
  end

  test "link_wallet POST with import_empty creates zero-balance accounts to sync later" do
    item = @user.family.coinstats_items.create!(name: "CoinStats", api_key: "csk-123")
    Provider::Coinstats.any_instance.stubs(:min_request_interval).returns(0)

    stub_request(:get, "#{BASE}/wallet/balances")
      .with(query: { "wallets" => "ethereum:0xabc,polygon:0xabc" })
      .to_return(status: 200, body: [].to_json, headers: { "Content-Type" => "application/json" })
    CoinstatsItem.any_instance.stubs(:sync_later)

    assert_difference "Account.count", 2 do
      post link_wallet_coinstats_item_url(item), params: { coinstats_item: { address: "0xabc", blockchain: [ "ethereum", "polygon" ], import_empty: "1" } }
    end

    assert_redirected_to accounts_url
  end

  test "link_wallet POST shows an actionable pt-BR message when credits are exhausted" do
    item = @user.family.coinstats_items.create!(name: "CoinStats", api_key: "csk-123")
    Provider::Coinstats.any_instance.stubs(:min_request_interval).returns(0)

    stub_request(:get, "#{BASE}/wallet/blockchains")
      .to_return(status: 200, body: [].to_json, headers: { "Content-Type" => "application/json" })
    stub_request(:get, "#{BASE}/wallet/balances")
      .with(query: { "wallets" => "ethereum:0xabc" })
      .to_return(status: 406, body: { statusCode: 406, message: "Credits limit reached." }.to_json, headers: { "Content-Type" => "application/json" })

    post link_wallet_coinstats_item_url(item), params: { coinstats_item: { address: "0xabc", blockchain: [ "ethereum" ] } }

    assert_response :unprocessable_entity
    assert_match(/créditos do CoinStats acabaram/i, response.body)
  end

  test "destroy schedules deletion" do
    item = @user.family.coinstats_items.create!(name: "CoinStats", api_key: "csk-123")

    delete coinstats_item_url(item)

    assert item.reload.scheduled_for_deletion?
    assert_equal I18n.t("coinstats_items.destroy.success"), flash[:notice]
  end

  test "sync enqueues a sync when not already syncing" do
    item = @user.family.coinstats_items.create!(name: "CoinStats", api_key: "csk-123")
    CoinstatsItem.any_instance.stubs(:syncing?).returns(false)
    CoinstatsItem.any_instance.expects(:sync_later).once

    post sync_coinstats_item_url(item)
    assert_response :redirect
  end
end
