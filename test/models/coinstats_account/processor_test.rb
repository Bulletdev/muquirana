require "test_helper"

class CoinstatsAccount::ProcessorTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
    @item = @family.coinstats_items.create!(name: "CoinStats", api_key: "key-123")
    @coinstats_account = @item.coinstats_accounts.create!(
      name: "Ethereum (0x123abc)",
      currency: "USD",
      account_id: "wallet:ethereum:0x123abc",
      wallet_address: "0x123abc",
      blockchain: "ethereum",
      current_balance: 4500
    )
  end

  test "creates the domain Account and converts the USD balance to the family currency" do
    skip "family currency is USD, nothing to convert" if @family.currency.to_s.upcase == "USD"

    ExchangeRate.create!(from_currency: "USD", to_currency: @family.currency, date: Date.current, rate: 5)

    account = nil
    assert_difference [ "Account.count", "AccountProvider.count" ], 1 do
      account = CoinstatsAccount::Processor.new(@coinstats_account).process
    end

    assert_equal "Crypto", account.accountable_type
    assert_equal @family.currency, account.currency
    assert_equal 22500.0, account.balance.to_f # 4500 USD * 5
    assert AccountProvider.exists?(account: account, provider_type: "CoinstatsAccount", provider_id: @coinstats_account.id)
  end

  test "degrades gracefully (stale) when no FX rate is available" do
    skip "family currency is USD, nothing to convert" if @family.currency.to_s.upcase == "USD"

    # Sem taxa em cache e sem provider -> find_or_fetch_rate devolve nil.
    ExchangeRate.stubs(:find_or_fetch_rate).returns(nil)

    account = CoinstatsAccount::Processor.new(@coinstats_account).process

    # Sem taxa: mantem o valor cru e marca stale, sem quebrar.
    assert_equal 4500.0, account.balance.to_f
    assert_equal true, @coinstats_account.reload.extra.dig("coinstats", "stale_rate")
  end
end
