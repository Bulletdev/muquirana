require "test_helper"

class AccountProviderTest < ActiveSupport::TestCase
  test "resolve o adapter do Plaid via factory e expoe provider_name" do
    ap = AccountProvider.create!(
      account: accounts(:depository),
      provider: plaid_accounts(:one)
    )

    assert_instance_of Provider::PlaidAdapter, ap.adapter
    assert_equal "plaid", ap.provider_name
    assert_equal plaid_accounts(:one), ap.provider
  end

  test "impede dois providers do mesmo tipo na mesma conta" do
    AccountProvider.create!(account: accounts(:depository), provider: plaid_accounts(:one))

    dup = AccountProvider.new(account: accounts(:depository), provider: plaid_accounts(:one))
    assert_not dup.valid?
  end
end
