require "test_helper"

class EntryTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @entry = entries :transaction
  end

  test "entry cannot be older than 10 years ago" do
    assert_raises ActiveRecord::RecordInvalid do
      @entry.update! date: 50.years.ago.to_date
    end
  end

  # Isolamento entre familias nas FKs de Transaction.
  #
  # Nao ha default_scope de tenant nem Pundit: o isolamento so existe enquanto a
  # query parte de Current.family. Um id de FK vindo de params escapa disso -- a
  # entry e da familia certa, mas category_id/merchant_id/tag_ids podem apontar
  # para fora dela. Todos os caminhos de escrita (API, web, Entry.bulk_update!,
  # transfers) passam por Entry com entryable_attributes, entao a validacao mora
  # aqui e os testes abaixo cobrem os quatro de uma vez.
  #
  # accounts(:depository) pertence a dylan_family; categories(:one), tags(:three)
  # e merchants(:one) pertencem a familia :empty.

  test "transaction cannot reference a category from another family" do
    entry = Entry.new(
      account: accounts(:depository), name: "x", date: Date.current,
      currency: "USD", amount: 10,
      entryable: Transaction.new(category: categories(:one))
    )

    assert_not entry.valid?
    assert_includes entry.errors.full_messages.join(" "), "Category must belong to the same family"
  end

  test "transaction cannot reference a tag from another family" do
    entry = Entry.new(
      account: accounts(:depository), name: "x", date: Date.current,
      currency: "USD", amount: 10,
      entryable: Transaction.new(tags: [ tags(:three) ])
    )

    assert_not entry.valid?
    assert_includes entry.errors.full_messages.join(" "), "Tags must belong to the same family"
  end

  test "transaction cannot reference a FamilyMerchant from another family" do
    entry = Entry.new(
      account: accounts(:depository), name: "x", date: Date.current,
      currency: "USD", amount: 10,
      entryable: Transaction.new(merchant: merchants(:one))
    )

    assert_not entry.valid?
    assert_includes entry.errors.full_messages.join(" "), "Merchant must belong to the same family"
  end

  # Guarda de regressao: ProviderMerchant (Plaid/Synth/AI) e global POR DESIGN e
  # nao tem family_id. Validar familia nele indiscriminadamente quebraria toda
  # transacao enriquecida por provider.
  test "transaction accepts a global ProviderMerchant" do
    provider_merchant = ProviderMerchant.create!(name: "Global Co", source: "plaid")

    entry = Entry.new(
      account: accounts(:depository), name: "x", date: Date.current,
      currency: "USD", amount: 10,
      entryable: Transaction.new(merchant: provider_merchant)
    )

    assert entry.valid?, entry.errors.full_messages.to_sentence
  end

  test "transaction accepts category, tag and merchant from its own family" do
    entry = Entry.new(
      account: accounts(:depository), name: "x", date: Date.current,
      currency: "USD", amount: 10,
      entryable: Transaction.new(
        category: categories(:income), merchant: merchants(:netflix), tags: [ tags(:one) ]
      )
    )

    assert entry.valid?, entry.errors.full_messages.to_sentence
  end

  test "bulk_update! rejects a category from another family" do
    assert_raises ActiveRecord::RecordInvalid do
      Entry.where(id: @entry.id).bulk_update!(category_id: categories(:one).id)
    end
  end

  test "valuations cannot have more than one entry per day" do
    existing_valuation = entries :valuation

    new_valuation = Entry.new \
      entryable: Valuation.new(kind: "reconciliation"),
      account: existing_valuation.account,
      date: existing_valuation.date, # invalid
      currency: existing_valuation.currency,
      amount: existing_valuation.amount

    assert new_valuation.invalid?
  end

  test "triggers sync with correct start date when transaction is set to prior date" do
    prior_date = @entry.date - 1
    @entry.update! date: prior_date

    @entry.account.expects(:sync_later).with(window_start_date: prior_date)
    @entry.sync_account_later
  end

  test "triggers sync with correct start date when transaction is set to future date" do
    prior_date = @entry.date
    @entry.update! date: @entry.date + 1

    @entry.account.expects(:sync_later).with(window_start_date: prior_date)
    @entry.sync_account_later
  end

  test "triggers sync with correct start date when transaction deleted" do
    @entry.destroy!

    @entry.account.expects(:sync_later).with(window_start_date: nil)
    @entry.sync_account_later
  end

  test "can search entries" do
    family = families(:empty)
    account = family.accounts.create! name: "Test", balance: 0, currency: "USD", accountable: Depository.new
    category = family.categories.first
    merchant = family.merchants.first

    create_transaction(account: account, name: "a transaction")
    create_transaction(account: account, name: "ignored")
    create_transaction(account: account, name: "third transaction", category: category, merchant: merchant)

    params = { search: "a" }

    assert_equal 2, family.entries.search(params).size

    params = { search: "%" }
    assert_equal 0, family.entries.search(params).size
  end

  test "visible scope only returns entries from visible accounts" do
    # Create transactions for all account types
    visible_transaction = create_transaction(account: accounts(:depository), name: "Visible transaction")
    invisible_transaction = create_transaction(account: accounts(:credit_card), name: "Invisible transaction")

    # Update account statuses
    accounts(:credit_card).disable!

    # Test the scope
    visible_entries = Entry.visible

    # Should include entry from active account
    assert_includes visible_entries, visible_transaction

    # Should not include entry from disabled account
    assert_not_includes visible_entries, invisible_transaction
  end
end
