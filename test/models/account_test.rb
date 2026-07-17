require "test_helper"

class AccountTest < ActiveSupport::TestCase
  include SyncableInterfaceTest, EntriesTestHelper

  setup do
    @account = @syncable = accounts(:depository)
    @family = families(:dylan_family)
  end

  test "can destroy" do
    assert_difference "Account.count", -1 do
      @account.destroy
    end
  end

  test "included_in_reports scope excludes accounts marked as exclude_from_reports" do
    included = @family.accounts.create! name: "Included", balance: 100, currency: "USD", accountable: Depository.new
    excluded = @family.accounts.create! name: "Excluded", balance: 200, currency: "USD", accountable: Depository.new, exclude_from_reports: true

    results = @family.accounts.included_in_reports
    assert_includes results, included
    assert_not_includes results, excluded
    assert_includes @family.accounts.excluded_from_reports, excluded
  end

  test "gets short/long subtype label" do
    account = @family.accounts.create!(
      name: "Test Investment",
      balance: 1000,
      currency: "USD",
      subtype: "hsa",
      accountable: Investment.new
    )

    # Rotulos de subtipo agora sao traduzidos (default_locale = pt-BR); compare
    # com o proprio lookup em vez de literal em ingles.
    assert_equal Investment.short_subtype_label_for("hsa"), account.short_subtype_label
    assert_equal Investment.long_subtype_label_for("hsa"), account.long_subtype_label

    # Test with nil subtype -- cai no display_name do accountable, que e
    # traduzido (default_locale = pt-BR); compare com o proprio display_name.
    account.update!(subtype: nil)
    assert_equal Investment.display_name, account.short_subtype_label
    assert_equal Investment.display_name, account.long_subtype_label
  end
end
