require "test_helper"

class BinanceItemsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_admin)
  end

  test "new renders the connection form" do
    get new_binance_item_url
    assert_response :success
  end

  test "create builds a binance item from pasted credentials and schedules a sync" do
    # Nao dispara o sync real (rede): so garante o enfileiramento.
    BinanceItem.any_instance.stubs(:sync_later)

    assert_difference "BinanceItem.count", 1 do
      post binance_items_url, params: {
        binance_item: { name: "Minha Binance", api_key: "abc", api_secret: "xyz" }
      }
    end

    item = BinanceItem.order(:created_at).last
    assert_equal "Minha Binance", item.name
    assert_equal "abc", item.api_key
    assert_equal "xyz", item.api_secret
    assert_equal I18n.t("binance_items.create.success"), flash[:notice]
  end

  test "create re-renders the form when credentials are missing" do
    assert_no_difference "BinanceItem.count" do
      post binance_items_url, params: { binance_item: { name: "X", api_key: "", api_secret: "" } }
    end

    assert_response :unprocessable_entity
  end

  test "destroy schedules deletion" do
    item = @user.family.binance_items.create!(name: "Binance", api_key: "k", api_secret: "s")

    delete binance_item_url(item)

    assert item.reload.scheduled_for_deletion?
    assert_equal I18n.t("binance_items.destroy.success"), flash[:notice]
  end

  test "sync enqueues a sync when not already syncing" do
    item = @user.family.binance_items.create!(name: "Binance", api_key: "k", api_secret: "s")
    BinanceItem.any_instance.stubs(:syncing?).returns(false)
    BinanceItem.any_instance.expects(:sync_later).once

    post sync_binance_item_url(item)
    assert_response :redirect
  end
end
