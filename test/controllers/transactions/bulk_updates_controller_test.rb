require "test_helper"

class Transactions::BulkUpdatesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_admin)
  end

  test "bulk update" do
    transactions = @user.family.entries.transactions

    # Escopados na familia do usuario logado. Antes usavam Category.second /
    # Merchant.second / Tag.first -- lookups globais que podiam devolver
    # registros de outra familia, e so passavam porque o Entry nao validava a
    # familia das FKs. Ver a validacao entryable_associations_belong_to_family.
    family = @user.family
    category = family.categories.first
    merchant = family.merchants.first
    tags = family.tags.first(2)

    assert_difference [ "Entry.count", "Transaction.count" ], 0 do
      post transactions_bulk_update_url, params: {
        bulk_update: {
          entry_ids: transactions.map(&:id),
          date: 1.day.ago.to_date,
          category_id: category.id,
          merchant_id: merchant.id,
          tag_ids: tags.map(&:id),
          notes: "Updated note"
        }
      }
    end

    assert_redirected_to transactions_url
    assert_equal "#{transactions.count} transactions updated", flash[:notice]

    transactions.reload.each do |transaction|
      assert_equal 1.day.ago.to_date, transaction.date
      assert_equal category, transaction.transaction.category
      assert_equal merchant, transaction.transaction.merchant
      assert_equal "Updated note", transaction.notes
      assert_equal tags.map(&:id).sort, transaction.entryable.tag_ids.sort
    end
  end

  # A validacao de familia precisa valer tambem no bulk update, que era um dos
  # cinco caminhos de escrita que atingiam a FK sem checagem.
  #
  # bulk_update! levanta RecordInvalid, que o rescue_responses do Rails mapeia
  # para 422 -- por isso a assercao e sobre a resposta, nao assert_raises.
  test "bulk update rejects a category from another family" do
    transactions = @user.family.entries.transactions
    foreign_category = categories(:one) # families(:empty)

    assert_not_equal @user.family, foreign_category.family
    categories_before = transactions.map { |e| e.entryable.category_id }

    post transactions_bulk_update_url, params: {
      bulk_update: {
        entry_ids: transactions.map(&:id),
        category_id: foreign_category.id
      }
    }

    assert_response :unprocessable_entity
    assert_equal categories_before, transactions.reload.map { |e| e.entryable.category_id },
      "nenhuma transacao pode ter sido alterada"
  end
end
