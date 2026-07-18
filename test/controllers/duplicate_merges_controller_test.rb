require "test_helper"

# US-03: controller de merge manual de duplicatas de reimportacao.
class DuplicateMergesControllerTest < ActionDispatch::IntegrationTest
  include EntriesTestHelper

  setup do
    sign_in @user = users(:family_admin)
    @account = accounts(:depository)
  end

  test "new renders the suggestion dialog" do
    original = create_transaction(account: @account, amount: 100, date: Date.current)
    create_transaction(account: @account, amount: 100, date: Date.current)

    get new_transaction_duplicate_merge_path(original)

    assert_response :success
  end

  test "create merges the selected duplicate into the current transaction" do
    survivor = create_transaction(account: @account, amount: 75, date: Date.current, name: "Farmácia")
    duplicate = create_transaction(account: @account, amount: 75, date: Date.current, name: "FARMACIA LTDA")

    assert_difference "Entry.count", -1 do
      post transaction_duplicate_merge_path(survivor), params: {
        duplicate_merge: { duplicate_entry_id: duplicate.id }
      }
    end

    assert_redirected_to transactions_url
    assert Entry.exists?(survivor.id)
    assert_not Entry.exists?(duplicate.id)
  end

  test "create rejects an ineligible entry" do
    survivor = create_transaction(account: @account, amount: 75, date: Date.current)
    not_a_candidate = create_transaction(account: @account, amount: 999, date: Date.current)

    assert_no_difference "Entry.count" do
      post transaction_duplicate_merge_path(survivor), params: {
        duplicate_merge: { duplicate_entry_id: not_a_candidate.id }
      }
    end

    assert_redirected_to transactions_url
    assert Entry.exists?(not_a_candidate.id)
  end

  test "dismiss keeps both transactions" do
    a = create_transaction(account: @account, amount: 60, date: Date.current, name: "Uber")
    create_transaction(account: @account, amount: 60, date: Date.current, name: "Uber")

    assert_no_difference "Entry.count" do
      post dismiss_transaction_duplicate_merge_path(a)
    end

    assert_redirected_to transactions_url
  end
end
