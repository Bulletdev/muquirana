require "test_helper"

class EntryTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @account = accounts(:depository)
    # Despesa: valor positivo pela convencao do app.
    @entry = create_transaction(account: @account, name: "Mercado", amount: 100)
  end

  # --- split! -------------------------------------------------------------

  test "split! creates children summing to parent and excludes the parent" do
    assert_difference -> { Entry.count } => 2, -> { Transaction.count } => 2 do
      @entry.split!([
        { name: "Alimentacao", amount: 80, category_id: categories(:food_and_drink).id },
        { name: "Higiene", amount: 20, category_id: nil }
      ])
    end

    @entry.reload
    assert @entry.split_parent?
    assert @entry.excluded?, "parent must be excluded (container)"
    assert_equal 2, @entry.child_entries.count
    assert_equal 100, @entry.child_entries.sum(:amount)
    assert_equal [ "Alimentacao", "Higiene" ], @entry.child_entries.order(:amount).reverse_order.pluck(:name)

    child = @entry.child_entries.find_by(name: "Alimentacao")
    assert child.split_child?
    assert_equal @entry.date, child.date
    assert_equal categories(:food_and_drink).id, child.transaction.category_id
  end

  test "split! keeps the parent sign for income (negative amount)" do
    income = create_transaction(account: @account, name: "Salario", amount: -100)

    income.split!([
      { name: "Base", amount: -60 },
      { name: "Bonus", amount: -40 }
    ])

    assert_equal(-100, income.child_entries.sum(:amount))
    assert income.child_entries.all? { |c| c.amount.negative? }
  end

  test "split! raises when amounts do not sum to parent" do
    assert_raises(ActiveRecord::RecordInvalid) do
      @entry.split!([
        { name: "A", amount: 80 },
        { name: "B", amount: 10 }
      ])
    end

    assert_not @entry.reload.split_parent?
    assert_not @entry.excluded?
  end

  # --- double counting (CRITICO) -----------------------------------------

  test "excluding_split_parents prevents double counting in balance sums" do
    original_sum = @account.entries.sum(:amount)

    @entry.split!([
      { name: "A", amount: 80 },
      { name: "B", amount: 20 }
    ])

    # Todas as entries somam em dobro (pai 100 + filhas 100).
    assert_equal original_sum + 100, @account.entries.sum(:amount)

    # A soma usada por saldo/relatorios (sem pais de split) permanece igual ao
    # valor original: as filhas substituem o pai, sem contar em dobro.
    assert_equal original_sum, @account.entries.excluding_split_parents.sum(:amount)
  end

  test "SyncCache excludes split parents from converted entries" do
    @entry.split!([
      { name: "A", amount: 80 },
      { name: "B", amount: 20 }
    ])

    cache = Balance::SyncCache.new(@account.reload)
    cached = cache.get_entries(@entry.date)

    assert_not_includes cached.map(&:id), @entry.id
    assert_equal 100, cached.select { |e| e.name.in?(%w[A B]) }.sum(&:amount)
  end

  # --- unsplit! -----------------------------------------------------------

  test "unsplit! removes children and restores the parent" do
    @entry.split!([
      { name: "A", amount: 80 },
      { name: "B", amount: 20 }
    ])

    assert_difference -> { Entry.count } => -2 do
      @entry.unsplit!
    end

    @entry.reload
    assert_not @entry.split_parent?
    assert_not @entry.excluded?
  end

  # --- protections --------------------------------------------------------

  test "a split child cannot be destroyed individually" do
    @entry.split!([ { name: "A", amount: 100 } ])
    child = @entry.child_entries.first

    assert_no_difference -> { Entry.count } do
      child.destroy
    end
    assert Entry.exists?(child.id)
  end

  test "split parent cannot be un-excluded" do
    @entry.split!([ { name: "A", amount: 100 } ])

    @entry.excluded = false
    assert_not @entry.valid?
    assert_includes @entry.errors[:excluded], "cannot be toggled off for a split transaction"
  end
end
