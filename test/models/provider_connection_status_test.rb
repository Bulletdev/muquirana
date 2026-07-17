require "test_helper"

class ProviderConnectionStatusTest < ActiveSupport::TestCase
  test "reporta status das conexoes Plaid da familia" do
    family = families(:dylan_family)

    statuses = ProviderConnectionStatus.for_family(family)

    plaid = statuses.find { |s| s[:provider] == "plaid" }
    assert plaid.present?, "esperava status para o item Plaid da familia"
    assert_equal "PlaidItem", plaid[:provider_type]
    assert plaid[:accounts].key?(:total_count)
    assert plaid[:accounts].key?(:linked_count)
  end
end
