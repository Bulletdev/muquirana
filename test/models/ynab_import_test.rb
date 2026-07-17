require "test_helper"

class YnabImportTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
  end

  test "default column mappings are applied after create" do
    import = @family.imports.create!(type: "YnabImport")

    YnabImport.default_column_mappings.each do |attribute, value|
      assert_equal value, import.public_send(attribute)
    end
  end

  test "outflow becomes a positive (expense) amount and inflow a negative (income) amount" do
    import = ynab_import(file_fixture("imports/ynab.csv").read)
    import.generate_rows_from_csv

    by_name = rows_by_name(import)
    # Aluguel e um outflow puro: despesa, armazenada positiva na convencao interna
    assert_equal BigDecimal("1500"), by_name["Landlord"].signed_amount
    # Salario e um inflow puro: receita, armazenada negativa na convencao interna
    assert_equal BigDecimal("-2500"), by_name["Employer"].signed_amount
  end

  test "strips currency symbols and thousands separators from outflow/inflow" do
    import = ynab_import(<<~CSV)
      Account,Date,Payee,Category Group/Category,Memo,Outflow,Inflow
      Checking,02/01/2024,Big Bill,Bills: Utilities,Quarterly,"$1,234.56",
      Checking,02/02/2024,Refund,Income: Refund,,,"$1,000.00"
    CSV
    import.generate_rows_from_csv

    by_name = rows_by_name(import)
    assert_equal BigDecimal("1234.56"), by_name["Big Bill"].signed_amount
    assert_equal BigDecimal("-1000"), by_name["Refund"].signed_amount
  end

  test "combines the category group and category from the single YNAB column" do
    import = ynab_import(file_fixture("imports/ynab.csv").read)
    import.generate_rows_from_csv

    assert_equal "Housing: Rent", rows_by_name(import)["Landlord"].category
  end

  test "composes separate Category Group and Category columns" do
    import = ynab_import(<<~CSV)
      Account,Date,Payee,Category Group,Category,Memo,Outflow,Inflow
      Checking,03/01/2024,Store,Food,Groceries,Weekly,42.00,0.00
      Checking,03/02/2024,Misc,Food,,No category,5.00,0.00
    CSV
    import.generate_rows_from_csv

    by_name = rows_by_name(import)
    assert_equal "Food: Groceries", by_name["Store"].category
    assert_equal "Food", by_name["Misc"].category
  end

  test "composes legacy YNAB 4 Master Category and Sub Category columns" do
    import = ynab_import(<<~CSV)
      Account,Date,Payee,Category,Master Category,Sub Category,Memo,Outflow,Inflow
      Checking,03/10/2024,Store,Everyday Expenses: Groceries,Everyday Expenses,Groceries,Weekly,42.00,0.00
      Checking,03/11/2024,Misc,Everyday Expenses,Everyday Expenses,,No sub,5.00,0.00
    CSV
    import.generate_rows_from_csv

    by_name = rows_by_name(import)
    assert_equal "Everyday Expenses: Groceries", by_name["Store"].category
    assert_equal "Everyday Expenses", by_name["Misc"].category
  end

  test "a single signed Amount column takes precedence over outflow/inflow" do
    import = ynab_import(<<~CSV)
      Account,Date,Payee,Category Group/Category,Memo,Amount
      Checking,04/01/2024,Employer,Income: Salary,Paycheck,2000.00
      Checking,04/02/2024,Store,Food: Groceries,Weekly,-50.00
    CSV
    import.generate_rows_from_csv

    by_name = rows_by_name(import)
    assert_equal BigDecimal("-2000"), by_name["Employer"].signed_amount  # inflow positivo -> receita negativa
    assert_equal BigDecimal("50"), by_name["Store"].signed_amount        # outflow negativo -> despesa positiva
  end

  test "blank payee falls back to memo, then to the default row name" do
    import = ynab_import(file_fixture("imports/ynab.csv").read)
    import.generate_rows_from_csv

    # A linha com Payee em branco cai no Memo significativo
    assert_includes import.rows.reload.map(&:name), "Reconciliation balance adjustment"

    blank_both = ynab_import(<<~CSV)
      Account,Date,Payee,Category Group/Category,Memo,Outflow,Inflow
      Checking,01/04/2024,,,,0.00,0.43
    CSV
    blank_both.generate_rows_from_csv

    assert_equal "Imported item", blank_both.rows.reload.sole.name
  end

  test "publishes entries with combined money movement and mapped category/account" do
    import = ynab_import(file_fixture("imports/ynab.csv").read)
    import.generate_rows_from_csv

    import.mappings.create! key: "Housing: Rent", create_when_empty: true, type: "Import::CategoryMapping"
    import.mappings.create! key: "Food: Coffee", create_when_empty: true, type: "Import::CategoryMapping"
    import.mappings.create! key: "Income: Paycheck", create_when_empty: true, type: "Import::CategoryMapping"
    import.mappings.create! key: "Checking", mappable: accounts(:depository), type: "Import::AccountMapping"
    import.mappings.create! key: "Credit Card", mappable: accounts(:credit_card), type: "Import::AccountMapping"
    import.reload

    assert_difference -> { Entry.count } => 5, -> { Transaction.count } => 5 do
      import.publish
    end

    assert_equal "complete", import.status

    entries = import.entries.reload
    assert_equal BigDecimal("1500"), entries.find { |e| e.name == "Landlord" }.amount   # despesa, positiva
    assert_equal BigDecimal("-2500"), entries.find { |e| e.name == "Employer" }.amount   # receita, negativa
  end

  test "nets the amount when both outflow and inflow are present on a row" do
    import = ynab_import(<<~CSV)
      Account,Date,Payee,Category Group/Category,Memo,Outflow,Inflow
      Checking,05/01/2024,Adjustment,Income: Adjust,Net,30.00,100.00
    CSV
    import.generate_rows_from_csv

    # inflow 100 - outflow 30 = +70 (receita), revertido para -70 na convencao interna
    assert_equal BigDecimal("-70"), import.rows.reload.sole.signed_amount
  end

  test "treats an already-signed (negative) outflow as a magnitude" do
    import = ynab_import(<<~CSV)
      Account,Date,Payee,Category Group/Category,Memo,Outflow,Inflow
      Checking,05/02/2024,Store,Food: Groceries,Signed,-25.00,
    CSV
    import.generate_rows_from_csv

    # Um outflow negativo ainda e uma despesa (+25 na convencao interna), nunca receita
    assert_equal BigDecimal("25"), import.rows.reload.sole.signed_amount
  end

  test "non-numeric outflow/inflow yields a zero amount instead of erroring" do
    import = ynab_import(<<~CSV)
      Account,Date,Payee,Category Group/Category,Memo,Outflow,Inflow
      Checking,05/03/2024,Weird,Food: Groceries,Garbage,n/a,
    CSV
    import.generate_rows_from_csv

    assert_equal BigDecimal("0"), import.rows.reload.sole.signed_amount
  end

  test "leaves the account blank when the export omits an Account column" do
    import = ynab_import(<<~CSV)
      Date,Payee,Category Group/Category,Memo,Outflow,Inflow
      05/04/2024,Store,Food: Groceries,No account column,5.00,
    CSV
    import.generate_rows_from_csv

    assert_equal "", import.rows.reload.sole.account
  end

  test "blocks the import when no Outflow/Inflow/Amount column is present" do
    import = ynab_import(<<~CSV)
      Account,Date,Payee,Category Group/Category,Memo
      Checking,01/01/2024,Store,Food: Groceries,No amount columns here
    CSV
    import.generate_rows_from_csv

    row = import.rows.reload.sole
    # Sem origem de valor -> valor em branco -> falha na validacao de coluna obrigatoria
    assert_predicate row.amount.to_s, :blank?
    assert_not row.valid?
    assert_includes row.errors[:amount], "is required"
    assert_not import.cleaned?
  end

  test "still allows a genuine zero-dollar row when amount columns exist" do
    import = ynab_import(<<~CSV)
      Account,Date,Payee,Category Group/Category,Memo,Outflow,Inflow
      Checking,01/01/2024,Placeholder,Food: Groceries,Zero,$0.00,$0.00
    CSV
    import.generate_rows_from_csv

    row = import.rows.reload.sole
    assert_equal BigDecimal("0"), row.signed_amount
    assert row.valid?
  end

  private
    # O Muquirana usa UUID como chave primaria, entao nao da para ordenar por :id
    # para recuperar a ordem do CSV. Indexamos as linhas pelo nome (payee), que e
    # unico em cada fixture de teste.
    def rows_by_name(import)
      import.rows.reload.index_by(&:name)
    end

    # As fixtures do YNAB usam o formato de numero US ($1,234.56). O default do
    # Muquirana e o pt-BR (1.234,56), entao fixamos o formato aqui - no app real o
    # usuario escolhe o formato na tela de configuracao da importacao.
    def ynab_import(csv)
      @family.imports.create!(
        type: "YnabImport",
        raw_file_str: csv,
        col_sep: ",",
        number_format: "1,234.56"
      )
    end
end
