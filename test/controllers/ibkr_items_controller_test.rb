require "test_helper"

class IbkrItemsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_admin)
  end

  test "new renders the connection form" do
    get new_ibkr_item_url
    assert_response :success
  end

  test "create builds an ibkr item from pasted query_id + token and schedules a sync" do
    # Nao dispara o sync real (rede): so garante o enfileiramento.
    IbkrItem.any_instance.stubs(:sync_later)

    assert_difference "IbkrItem.count", 1 do
      post ibkr_items_url, params: {
        ibkr_item: { name: "Minha IBKR", query_id: "123456", token: "TOKEN" }
      }
    end

    item = IbkrItem.order(:created_at).last
    assert_equal "Minha IBKR", item.name
    assert_equal "123456", item.query_id
    assert_equal "TOKEN", item.token
    assert_equal I18n.t("ibkr_items.create.success"), flash[:notice]
  end

  test "create re-renders the form when credentials are missing" do
    assert_no_difference "IbkrItem.count" do
      post ibkr_items_url, params: { ibkr_item: { name: "X", query_id: "", token: "" } }
    end

    assert_response :unprocessable_entity
  end

  test "destroy schedules deletion" do
    item = @user.family.ibkr_items.create!(name: "IBKR", query_id: "q", token: "t")

    delete ibkr_item_url(item)

    assert item.reload.scheduled_for_deletion?
    assert_equal I18n.t("ibkr_items.destroy.success"), flash[:notice]
  end

  test "sync enqueues a sync when not already syncing" do
    item = @user.family.ibkr_items.create!(name: "IBKR", query_id: "q", token: "t")
    IbkrItem.any_instance.stubs(:syncing?).returns(false)
    IbkrItem.any_instance.expects(:sync_later).once

    post sync_ibkr_item_url(item)
    assert_response :redirect
  end
end
