require "test_helper"

# US-03: heuristica de candidatos a duplicata + merge manual (reimport CSV/OFX).
class TransactionDuplicateTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @account = accounts(:depository)
    @other_account = accounts(:credit_card)
  end

  test "suggests entries with same account, currency, amount and date within window" do
    original = create_transaction(account: @account, amount: 100, date: Date.current, name: "Mercado")
    dup = create_transaction(account: @account, amount: 100, date: Date.current, name: "MERCADO LTDA")

    candidate_ids = original.entryable.duplicate_candidates.pluck(:id)

    assert_includes candidate_ids, dup.id
    assert_not_includes candidate_ids, original.id, "nao deve sugerir a si mesmo"
  end

  test "includes candidates within the day window and excludes those outside it" do
    original = create_transaction(account: @account, amount: 50, date: Date.current)
    inside = create_transaction(account: @account, amount: 50, date: Date.current - 2)
    outside = create_transaction(account: @account, amount: 50, date: Date.current - 10)

    candidate_ids = original.entryable.duplicate_candidates(window_days: 3).pluck(:id)

    assert_includes candidate_ids, inside.id
    assert_not_includes candidate_ids, outside.id
  end

  test "excludes different amount, currency and account" do
    original = create_transaction(account: @account, amount: 100, date: Date.current, currency: "USD")
    diff_amount = create_transaction(account: @account, amount: 101, date: Date.current, currency: "USD")
    diff_account = create_transaction(account: @other_account, amount: 100, date: Date.current, currency: "USD")

    candidate_ids = original.entryable.duplicate_candidates.pluck(:id)

    assert_not_includes candidate_ids, diff_amount.id
    assert_not_includes candidate_ids, diff_account.id
  end

  test "merge keeps survivor and destroys duplicate without losing data" do
    category = categories(:food_and_drink)
    merchant = merchants(:amazon)

    survivor = create_transaction(account: @account, amount: 30, date: Date.current, name: "PADARIA")
    duplicate = create_transaction(
      account: @account, amount: 30, date: Date.current, name: "Padaria do Zé",
      category: category, merchant: merchant
    )
    duplicate.update!(notes: "comprado no débito")

    assert_difference [ "Entry.count", "Transaction.count" ], -1 do
      assert survivor.entryable.merge_duplicate!(duplicate)
    end

    assert_not Entry.exists?(duplicate.id), "duplicata deve ser destruida"
    survivor.reload

    # Sobrevivente herda dados que nao tinha.
    assert_equal category.id, survivor.entryable.category_id
    assert_equal merchant.id, survivor.entryable.merchant_id
    assert_equal "comprado no débito", survivor.notes
  end

  test "merge does not overwrite survivor data that is already present" do
    survivor_category = categories(:food_and_drink)
    dup_category = categories(:income)

    survivor = create_transaction(account: @account, amount: 40, date: Date.current, category: survivor_category)
    duplicate = create_transaction(account: @account, amount: 40, date: Date.current, category: dup_category)

    survivor.entryable.merge_duplicate!(duplicate)
    survivor.reload

    assert_equal survivor_category.id, survivor.entryable.category_id, "nao sobrescreve categoria existente"
  end

  test "merge refuses cross-account and self" do
    entry = create_transaction(account: @account, amount: 20, date: Date.current)
    cross = create_transaction(account: @other_account, amount: 20, date: Date.current)

    assert_not entry.entryable.merge_duplicate!(cross)
    assert_not entry.entryable.merge_duplicate!(entry)
    assert Entry.exists?(cross.id)
    assert Entry.exists?(entry.id)
  end

  test "legitimate collision of two identical transactions is only suggested, never auto merged" do
    a = create_transaction(account: @account, amount: 15, date: Date.current, name: "Uber")
    b = create_transaction(account: @account, amount: 15, date: Date.current, name: "Uber")

    # A heuristica os sugere um ao outro...
    assert_includes a.entryable.duplicate_candidates.pluck(:id), b.id

    # ...mas so consultar/sugerir nao destroi nada.
    assert Entry.exists?(a.id)
    assert Entry.exists?(b.id)
    assert_equal 2, Entry.where(id: [ a.id, b.id ]).count
  end
end
