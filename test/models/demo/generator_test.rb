require "test_helper"

# Garante que o seed de demonstracao nasce em portugues brasileiro.
#
# O gerador veio do Maybe com dados em ingles ("Salary", "Housing", "Whole
# Foods"...) que apareciam na demo -- a vitrine do projeto. Este teste trava a
# traducao: se alguem reintroduzir um nome em ingles, ou o proximo merge do
# upstream trouxer dados novos sem traduzir, ele quebra.
#
# O seed cria milhares de transacoes e e caro. Por isso ha UM teste que semeia
# uma vez e afirma tudo -- semear por teste (o Rails faz rollback entre eles)
# rodaria o seed inteiro varias vezes e estouraria o tempo.
#
# `sync_family_accounts!` e stubado: ele roda um Sync real por conta, que em
# teste tenta a API do Plaid com a credencial fake do CI e estoura. O sync
# calcula saldo; nao tem relacao com o IDIOMA dos dados, que e o que se afirma.
class Demo::GeneratorTest < ActiveSupport::TestCase
  # Palavras que so apareceriam se um dado voltasse ao ingles do upstream.
  ENGLISH_MARKERS = %w[
    Salary Housing Food Dining Groceries Restaurants Coffee Transportation
    Gas Payment Entertainment Healthcare Shopping Travel Personal Care
    Insurance Miscellaneous Loan Interest Checking Savings Chase Vanguard
    Fidelity Whole Foods Walmart Target Payroll Mortgage
    Deposit Initial Brokerage Store Diner Adjust Balance Dividends Restaurant Metro General Corner
  ].freeze
  # NAO entram como marcador (dariam falso positivo em dado que e pt-BR ou
  # marca legitima mantida de proposito):
  #   Freelance -> loanword corrente em pt-BR
  #   Netflix, Kindle -> marcas presentes no Brasil, mantidas no seed

  test "o seed nasce inteiro em portugues brasileiro" do
    Demo::Generator.any_instance.stubs(:sync_family_accounts!)

    Demo::Generator.new(seed: 1).generate_default_data!(skip_clear: true, email: "demo@muquirana.local")
    family = User.find_by(email: "demo@muquirana.local").family

    # roda ate o fim
    assert family.accounts.any?,     "a demo tem que ter contas"
    assert family.transactions.any?, "a demo tem que ter transacoes"
    assert family.categories.any?,   "a demo tem que ter categorias"

    # categorias em pt-BR
    cats = family.categories.pluck(:name)
    assert_includes cats, "Salário"
    assert_includes cats, "Moradia"
    assert_includes cats, "Alimentação"
    refute_english cats, "categorias"

    # contas em pt-BR, com banco brasileiro
    contas = family.accounts.pluck(:name)
    assert contas.any? { |n| n.include?("Nubank") || n.include?("Inter") }, "esperava banco brasileiro"
    refute_english contas, "contas"

    # nomes de transacao em pt-BR
    txns = family.transactions.joins(:entry).map { |t| t.entry.name }.uniq
    refute_english txns, "transacoes"

    # familia e admin com nome apresentavel (nao "Demo (admin)")
    admin = family.users.find_by(role: :admin)
    assert_equal "Família Souza", family.name
    assert_equal "Ana", admin.first_name
    refute_match(/Demo/, admin.first_name)
  end

  # Usa generate_empty_data! (familia + usuarios, SEM as milhares de
  # transacoes) porque este teste so verifica os NOMES, que vem do mesmo
  # create_family_and_users! de todos os modos. Evita pagar ~80s de um seed
  # completo so para ler dois nomes.
  test "DEMO_ADMIN_NAME e DEMO_FAMILY_NAME personalizam os nomes" do
    with_env_overrides DEMO_ADMIN_NAME: "Michael Souza", DEMO_FAMILY_NAME: "Família Silva" do
      Demo::Generator.new(seed: 1).generate_empty_data!(skip_clear: true)
      family = User.find_by(email: "user@muquirana.local").family
      admin = family.users.find_by(role: :admin)

      assert_equal "Michael", admin.first_name
      assert_equal "Souza", admin.last_name
      assert_equal "Família Silva", family.name
    end
  end

  private

    def refute_english(strings, contexto)
      encontrados = strings.select do |s|
        palavras = s.to_s.split(/[\s\/&.,()-]+/)
        ENGLISH_MARKERS.any? { |w| palavras.include?(w) }
      end

      assert_empty encontrados,
        "#{contexto} ainda com nome em ingles: #{encontrados.uniq.join(", ")}"
    end
end
