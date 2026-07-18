require "test_helper"
require "webmock/minitest"

class CoinstatsItem::SyncerTest < ActiveSupport::TestCase
  BASE = Provider::Coinstats::BASE_URL

  setup do
    @family = families(:dylan_family)
    @item = @family.coinstats_items.create!(name: "CoinStats", api_key: "key-123")
    # Uma carteira ja vinculada, para o importer iterar e bater na API stubada.
    @item.coinstats_accounts.create!(
      name: "Ethereum (0x123abc)",
      currency: "USD",
      account_id: "wallet:ethereum:0x123abc",
      wallet_address: "0x123abc",
      blockchain: "ethereum",
      current_balance: 0
    )
    Provider::Coinstats.any_instance.stubs(:min_request_interval).returns(0)
    Provider::Coinstats.any_instance.stubs(:sleep)
    @sync = Struct.new(:window_start_date, :window_end_date).new(nil, nil)
  end

  def stub_balances_status(status, body)
    stub_request(:get, "#{BASE}/wallet/balances")
      .with(query: { "wallets" => "ethereum:0x123abc" })
      .to_return(status: status, body: body, headers: { "Content-Type" => "application/json" })
  end

  test "translates HTTP 406 (credits) into an actionable pt-BR message and marks requires_update" do
    stub_balances_status(406, { statusCode: 406, message: "Credits limit reached." }.to_json)

    assert_raises(Provider::Coinstats::Error) do
      CoinstatsItem::Syncer.new(@item).perform_sync(@sync)
    end

    @item.reload
    assert_equal "requires_update", @item.status
    assert_match(/créditos do CoinStats acabaram/i, @item.last_error)
  end

  test "translates HTTP 429 (rate-limit) into an actionable pt-BR message" do
    stub_balances_status(429, { message: "Too Many Requests" }.to_json)

    assert_raises(Provider::Coinstats::Error) do
      CoinstatsItem::Syncer.new(@item).perform_sync(@sync)
    end

    @item.reload
    assert_equal "requires_update", @item.status
    assert_match(/limitou temporariamente/i, @item.last_error)
  end

  test "translates HTTP 401 (auth) into an actionable pt-BR message" do
    stub_balances_status(401, { message: "Unauthorized" }.to_json)

    assert_raises(Provider::Coinstats::Error) do
      CoinstatsItem::Syncer.new(@item).perform_sync(@sync)
    end

    @item.reload
    assert_equal "requires_update", @item.status
    assert_match(/recusou a sua chave/i, @item.last_error)
  end

  test "missing credentials fails with actionable message without hitting the API" do
    @item.stubs(:credentials_configured?).returns(false)

    assert_raises(Provider::Coinstats::Error) do
      CoinstatsItem::Syncer.new(@item).perform_sync(@sync)
    end

    @item.reload
    assert_equal "requires_update", @item.status
    assert_match(/chave da API do CoinStats não foi informada/i, @item.last_error)
  end
end
