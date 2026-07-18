require "test_helper"

class SplitsControllerTest < ActionDispatch::IntegrationTest
  include EntriesTestHelper

  setup do
    sign_in @user = users(:family_admin)
    @entry = create_transaction(account: accounts(:depository), name: "Mercado", amount: 100)
  end

  test "new renders the split form" do
    get new_transaction_split_path(@entry)
    assert_response :success
  end

  test "create splits a transaction into children" do
    assert_difference [ "Entry.count", "Transaction.count" ], 2 do
      post transaction_split_path(@entry), params: {
        split: {
          splits: {
            "0" => { name: "Alimentacao", amount: "80", category_id: categories(:food_and_drink).id },
            "1" => { name: "Higiene", amount: "20", category_id: "" }
          }
        }
      }
    end

    @entry.reload
    assert @entry.split_parent?
    assert @entry.excluded?
    assert_equal 100, @entry.child_entries.sum(:amount)
    assert_enqueued_with(job: SyncJob)
  end

  test "create rejects a non-matching sum" do
    assert_no_difference "Entry.count" do
      post transaction_split_path(@entry), params: {
        split: { splits: { "0" => { name: "A", amount: "80" }, "1" => { name: "B", amount: "5" } } }
      }
    end

    assert_not @entry.reload.split_parent?
  end

  test "create rejects a non-splittable transaction" do
    @entry.update!(excluded: true)

    assert_no_difference "Entry.count" do
      post transaction_split_path(@entry), params: {
        split: { splits: { "0" => { name: "A", amount: "100" } } }
      }
    end

    assert_not @entry.reload.split_parent?
  end

  test "create is scoped to the current family" do
    # @entry pertence a dylan_family; um usuario de outra familia nao o alcanca.
    sign_in users(:empty)

    assert_no_difference "Entry.count" do
      post transaction_split_path(@entry), params: {
        split: { splits: { "0" => { name: "A", amount: "100" } } }
      }
    end

    assert_response :not_found
    assert_not @entry.reload.split_parent?
  end

  test "edit resolves a child to its parent" do
    @entry.split!([ { name: "A", amount: 60 }, { name: "B", amount: 40 } ])
    child = @entry.child_entries.first

    get edit_transaction_split_path(child)
    assert_response :success
  end

  test "update re-splits the transaction" do
    @entry.split!([ { name: "A", amount: 60 }, { name: "B", amount: 40 } ])

    patch transaction_split_path(@entry), params: {
      split: {
        splits: {
          "0" => { name: "X", amount: "70" },
          "1" => { name: "Y", amount: "30" }
        }
      }
    }

    @entry.reload
    assert_equal %w[X Y], @entry.child_entries.order(:amount).reverse_order.pluck(:name)
    assert_equal 100, @entry.child_entries.sum(:amount)
  end

  test "destroy unsplits the transaction" do
    @entry.split!([ { name: "A", amount: 60 }, { name: "B", amount: 40 } ])

    assert_difference "Entry.count", -2 do
      delete transaction_split_path(@entry)
    end

    @entry.reload
    assert_not @entry.split_parent?
    assert_not @entry.excluded?
  end
end
