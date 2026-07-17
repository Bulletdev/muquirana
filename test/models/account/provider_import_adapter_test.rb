require "test_helper"

# Prova da fundacao generica de providers: a regra de dedup CROSS-source
# (Plaid/provider vs. manual/CSV) decidida pelo dono do produto -- "manual vence".
#
# Tres pontos, os tres afirmados aqui:
#   1. Campo EDITADO/TRAVADO pelo usuario: o provider NUNCA sobrescreve.
#   2. Campo VAZIO: o provider PREENCHE o que o usuario nao definiu (complementa,
#      nao sobrescreve).
#   3. Chave de match = data + valor + conta. Dois lancamentos legitimos identicos
#      (dois cafes no mesmo dia/conta) NAO podem ser fundidos num so.
class Account::ProviderImportAdapterTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:depository) # conta manual (sem provider) da dylan_family
    @adapter = Account::ProviderImportAdapter.new(@account)
    @date = Date.current
  end

  # --- Ponto 1: campo travado pelo usuario nunca e sobrescrito -----------------
  test "provider nao sobrescreve campos travados pelo usuario (manual vence)" do
    manual = create_manual_entry(amount: 50, name: "Cafe do usuario", category_id: categories(:income).id)
    # Usuario editou nome e categoria e ambos ficam travados (caminho real de edicao)
    manual.lock_attr!(:name)
    manual.transaction.lock_attr!(:category_id)

    assert_no_difference "Entry.count" do
      @adapter.import_transaction(
        external_id: "plaid_1",
        source: "plaid",
        amount: 50,
        currency: "USD",
        date: @date,
        name: "STARBUCKS",                       # provider tenta trocar o nome
        category_id: categories(:food_and_drink).id # provider tenta trocar a categoria
      )
    end

    manual.reload
    assert_equal "Cafe do usuario", manual.name, "nome travado nao pode mudar"
    assert_equal categories(:income).id, manual.transaction.category_id, "categoria travada nao pode mudar"
    # Ainda assim o provider "reivindica" a entry (linka o external_id) sem sobrescrever
    assert_equal "plaid_1", manual.external_id
    assert_equal "plaid", manual.source
  end

  # --- Ponto 2: campo vazio e complementado pelo provider ----------------------
  test "provider preenche campo vazio que o usuario nao definiu (complementa)" do
    manual = create_manual_entry(amount: 75, name: "Mercado", category_id: nil)
    assert_nil manual.transaction.category_id

    @adapter.import_transaction(
      external_id: "plaid_2",
      source: "plaid",
      amount: 75,
      currency: "USD",
      date: @date,
      name: "Mercado",
      category_id: categories(:food_and_drink).id
    )

    manual.reload
    assert_equal categories(:food_and_drink).id, manual.transaction.category_id,
      "categoria vazia deve ser preenchida pelo provider"
  end

  # --- Ponto 3: dois lancamentos identicos NAO podem ser fundidos --------------
  test "dois lancamentos legitimos identicos no mesmo dia/conta nao sao fundidos" do
    # Usuario tem UM lancamento manual (um cafe). O provider traz DOIS cafes
    # identicos (mesma data/valor). Resultado esperado: DUAS entries, nao uma.
    create_manual_entry(amount: 20, name: "Cafe")

    assert_difference "Transaction.count", 1 do
      # primeiro cafe do provider reivindica o manual existente
      @adapter.import_transaction(
        external_id: "coffee_1", source: "plaid",
        amount: 20, currency: "USD", date: @date, name: "COFFEE SHOP"
      )
      # segundo cafe do provider NAO pode reusar o mesmo manual -> cria nova entry
      @adapter.import_transaction(
        external_id: "coffee_2", source: "plaid",
        amount: 20, currency: "USD", date: @date, name: "COFFEE SHOP"
      )
    end

    coffees = @account.entries.where(entryable_type: "Transaction", amount: 20, date: @date)
    assert_equal 2, coffees.count, "os dois cafes devem permanecer como duas entries distintas"
    assert_equal %w[coffee_1 coffee_2].sort, coffees.map(&:external_id).sort,
      "cada cafe deve ter seu proprio external_id (nada foi fundido)"
  end

  # --- Idempotencia: reimportar a mesma transacao nao duplica ------------------
  test "reimportar a mesma transacao do provider e idempotente" do
    @adapter.import_transaction(
      external_id: "p_idem", source: "plaid",
      amount: 30, currency: "USD", date: @date, name: "Loja"
    )

    assert_no_difference "Entry.count" do
      @adapter.import_transaction(
        external_id: "p_idem", source: "plaid",
        amount: 30, currency: "USD", date: @date, name: "Loja"
      )
    end
  end

  private
    def create_manual_entry(amount:, name:, category_id: nil)
      entry = @account.entries.create!(
        amount: amount,
        currency: "USD",
        date: @date,
        name: name,
        entryable: Transaction.new(category_id: category_id)
      )
      entry
    end
end
