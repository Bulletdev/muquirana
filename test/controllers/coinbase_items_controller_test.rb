require "test_helper"

class CoinbaseItemsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_admin)
  end

  test "new renders the connection form" do
    get new_coinbase_item_url
    assert_response :success
  end

  test "create builds a coinbase item from pasted credentials and schedules a sync" do
    # Nao dispara o sync real (rede): so garante o enfileiramento.
    CoinbaseItem.any_instance.stubs(:sync_later)

    assert_difference "CoinbaseItem.count", 1 do
      post coinbase_items_url, params: {
        coinbase_item: { name: "Minha Coinbase", api_key: "org/key", api_secret: "pem" }
      }
    end

    item = CoinbaseItem.order(:created_at).last
    assert_equal "Minha Coinbase", item.name
    assert_equal "org/key", item.api_key
    assert_equal "pem", item.api_secret
    assert_equal I18n.t("coinbase_items.create.success"), flash[:notice]
  end

  test "create re-renders the form when credentials are missing" do
    assert_no_difference "CoinbaseItem.count" do
      post coinbase_items_url, params: { coinbase_item: { name: "X", api_key: "", api_secret: "" } }
    end

    assert_response :unprocessable_entity
  end

  test "destroy schedules deletion" do
    item = @user.family.coinbase_items.create!(name: "Coinbase", api_key: "k", api_secret: "s")

    delete coinbase_item_url(item)

    assert item.reload.scheduled_for_deletion?
    assert_equal I18n.t("coinbase_items.destroy.success"), flash[:notice]
  end

  test "sync enqueues a sync when not already syncing" do
    item = @user.family.coinbase_items.create!(name: "Coinbase", api_key: "k", api_secret: "s")
    CoinbaseItem.any_instance.stubs(:syncing?).returns(false)
    CoinbaseItem.any_instance.expects(:sync_later).once

    post sync_coinbase_item_url(item)
    assert_response :redirect
  end
end
