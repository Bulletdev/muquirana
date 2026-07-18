require "test_helper"

class MercadoBitcoinItemsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_admin)
  end

  test "new renders the connection form" do
    get new_mercado_bitcoin_item_url
    assert_response :success
  end

  test "create builds a mercado bitcoin item from pasted credentials and schedules a sync" do
    # Nao dispara o sync real (rede): so garante o enfileiramento.
    MercadoBitcoinItem.any_instance.stubs(:sync_later)

    assert_difference "MercadoBitcoinItem.count", 1 do
      post mercado_bitcoin_items_url, params: {
        mercado_bitcoin_item: { name: "Minha MB", api_key: "abc", api_secret: "xyz" }
      }
    end

    item = MercadoBitcoinItem.order(:created_at).last
    assert_equal "Minha MB", item.name
    assert_equal "abc", item.api_key
    assert_equal "xyz", item.api_secret
    assert_equal I18n.t("mercado_bitcoin_items.create.success"), flash[:notice]
  end

  test "create re-renders the form when credentials are missing" do
    assert_no_difference "MercadoBitcoinItem.count" do
      post mercado_bitcoin_items_url, params: { mercado_bitcoin_item: { name: "X", api_key: "", api_secret: "" } }
    end

    assert_response :unprocessable_entity
  end

  test "destroy schedules deletion" do
    item = @user.family.mercado_bitcoin_items.create!(name: "Mercado Bitcoin", api_key: "k", api_secret: "s")

    delete mercado_bitcoin_item_url(item)

    assert item.reload.scheduled_for_deletion?
    assert_equal I18n.t("mercado_bitcoin_items.destroy.success"), flash[:notice]
  end

  test "sync enqueues a sync when not already syncing" do
    item = @user.family.mercado_bitcoin_items.create!(name: "Mercado Bitcoin", api_key: "k", api_secret: "s")
    MercadoBitcoinItem.any_instance.stubs(:syncing?).returns(false)
    MercadoBitcoinItem.any_instance.expects(:sync_later).once

    post sync_mercado_bitcoin_item_url(item)
    assert_response :redirect
  end
end
