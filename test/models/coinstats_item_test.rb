require "test_helper"

class CoinstatsItemTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
    @item = @family.coinstats_items.create!(name: "CoinStats", api_key: "csk-123")
  end

  test "api_key is encrypted at rest" do
    raw = ActiveRecord::Base.connection.select_value(
      "SELECT api_key FROM coinstats_items WHERE id = '#{@item.id}'"
    )
    assert_not_equal "csk-123", raw
    assert_equal "csk-123", @item.reload.api_key
  end

  test "sets CoinStats institution defaults on create" do
    assert_equal "CoinStats", @item.institution_name
    assert_equal "coinstats.app", @item.institution_domain
  end

  test "requires name and api_key" do
    item = @family.coinstats_items.build(name: "", api_key: "")
    refute item.valid?
    assert item.errors[:name].present?
    assert item.errors[:api_key].present?
  end

  test "credentials_configured? reflects api_key presence" do
    assert @item.credentials_configured?
  end

  test "destroy_later flags the item for deletion" do
    @item.destroy_later
    assert @item.reload.scheduled_for_deletion?
  end

  test "family can always connect coinstats" do
    assert @family.can_connect_coinstats?
  end
end
