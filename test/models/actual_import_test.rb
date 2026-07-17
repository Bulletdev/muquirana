require "test_helper"

class ActualImportTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
  end

  test "default column mappings are applied after create" do
    import = @family.imports.create!(type: "ActualImport")

    ActualImport.default_column_mappings.each do |attribute, value|
      assert_equal value, import.public_send(attribute)
    end
  end

  test "generated rows combine category group and category" do
    import = actual_import(file_fixture("imports/actual.csv").read)
    import.generate_rows_from_csv

    by_name = rows_by_name(import)
    assert_equal "Food: Coffee", by_name["Coffee Shop"].category
    assert_equal "Income: Paycheck", by_name["Employer"].category
    assert_equal "Transfer", by_name["Internal Transfer"].category
  end

  test "generated rows fall back to category group when category is blank" do
    import = actual_import(file_fixture("imports/actual.csv").read.sub("Housing,Rent", "Housing,"))
    import.generate_rows_from_csv

    assert_equal "Housing", rows_by_name(import)["Landlord"].category
  end

  test "blank payee falls back to notes, then to the default row name" do
    import = actual_import(file_fixture("imports/actual.csv").read)
    import.generate_rows_from_csv

    # A linha de reconciliacao tem Payee em branco, mas um Notes significativo
    assert_includes import.rows.reload.map(&:name), "Reconciliation balance adjustment"

    # Quando Payee e Notes estao ambos em branco, cai no nome default generico
    blank_both_csv = <<~CSV
      Account,Date,Payee,Notes,Category_Group,Category,Amount,Split_Amount,Cleared
      Checking Account,2024-01-04,,,Income,Income,0.43,0,Reconciled
    CSV

    blank_both = actual_import(blank_both_csv)
    blank_both.generate_rows_from_csv

    assert_equal "Imported item", blank_both.rows.reload.sole.name
  end

  test "imports rows with a blank payee without failing the whole import" do
    csv = <<~CSV
      Account,Date,Payee,Notes,Category_Group,Category,Amount,Split_Amount,Cleared
      Cash,2024-01-01,Employer,Salary,Income,Paycheck,2500.00,0,Reconciled
      Cash,2024-01-04,,Reconciliation balance adjustment,Income,Income,0.43,0,Reconciled
    CSV

    import = actual_import(csv)
    import.generate_rows_from_csv

    import.mappings.create! key: "Income: Paycheck", create_when_empty: true, type: "Import::CategoryMapping"
    import.mappings.create! key: "Income: Income", create_when_empty: true, type: "Import::CategoryMapping"
    import.mappings.create! key: "Cash", mappable: accounts(:depository), type: "Import::AccountMapping"
    import.reload

    assert_difference -> { Entry.count } => 2, -> { Transaction.count } => 2 do
      import.publish
    end

    assert_equal "complete", import.status
    assert_includes import.entries.reload.map(&:name), "Reconciliation balance adjustment"
  end

  private
    # O Muquirana usa UUID como chave primaria, entao nao da para ordenar por :id
    # para recuperar a ordem do CSV. Indexamos as linhas pelo nome (payee), que e
    # unico em cada fixture de teste.
    def rows_by_name(import)
      import.rows.reload.index_by(&:name)
    end

    # As fixtures do Actual Budget usam ponto como separador decimal (US). O default
    # do Muquirana e o pt-BR (1.234,56), entao fixamos o formato aqui - no app real o
    # usuario escolhe o formato na tela de configuracao da importacao.
    def actual_import(csv)
      @family.imports.create!(
        type: "ActualImport",
        raw_file_str: csv,
        col_sep: ",",
        number_format: "1,234.56"
      )
    end
end
