require "test_helper"

class QifImportTest < ActiveSupport::TestCase
  setup do
    @family  = families(:dylan_family)
    @account = accounts(:depository)
  end

  test "default config is applied after create" do
    import = @family.imports.create!(type: "QifImport")

    assert_equal "inflows_positive", import.signage_convention
    assert_equal "%Y-%m-%d", import.date_format
    assert_equal "1,234.56", import.number_format
    assert_not import.requires_csv_workflow?
  end

  test "parses transactions from a real QIF fixture, skipping the opening balance" do
    import = qif_import(file_fixture("imports/transactions.qif").read)
    import.generate_rows_from_csv

    by_name = rows_by_name(import)

    # A linha "Opening Balance" nao vira transacao
    assert_not_includes by_name.keys, "Opening Balance"
    assert_equal 4, import.rows.count

    # Datas parseadas para ISO 8601
    assert_equal "2024-01-03", by_name["Landlord"].date
    assert_equal "2024-01-10", by_name["Employer"].date

    # Valores (o parser mantem o sinal do campo T)
    assert_equal BigDecimal("-1500.00"), by_name["Landlord"].amount.to_d
    assert_equal BigDecimal("3200.00"), by_name["Employer"].amount.to_d
    assert_equal BigDecimal("-88.90"), by_name["Supermarket"].amount.to_d

    # Notas (campo M)
    assert_equal "January rent", by_name["Landlord"].notes
  end

  test "extracts categories and tags from the L field" do
    import = qif_import(file_fixture("imports/transactions.qif").read)
    import.generate_rows_from_csv

    by_name = rows_by_name(import)

    assert_equal "Housing", by_name["Landlord"].category
    assert_equal [ "Recurring" ], by_name["Landlord"].tags_list

    assert_equal "Food & Dining", by_name["Coffee Shop"].category
    assert_equal [ "" ], by_name["Coffee Shop"].tags_list

    assert_equal [ "Housing", "Food & Dining", "Income:Salary" ].sort, import.row_categories
    assert_equal [ "Recurring" ], import.row_tags
  end

  test "parses the opening balance record" do
    import = qif_import(file_fixture("imports/transactions.qif").read)
    ob = QifParser.parse_opening_balance(import.raw_file_str, date_format: import.qif_date_format)

    assert_equal Date.new(2024, 1, 2), ob[:date]
    assert_equal BigDecimal("2500.00"), ob[:amount]
  end

  test "signage: expenses become positive, income negative in the internal convention" do
    import = qif_import(file_fixture("imports/transactions.qif").read)
    import.generate_rows_from_csv

    by_name = rows_by_name(import)

    # Despesa (T negativo) -> positiva na convencao interna do Maybe
    assert_equal BigDecimal("1500.00"), by_name["Landlord"].signed_amount
    # Receita (T positivo) -> negativa na convencao interna
    assert_equal BigDecimal("-3200.00"), by_name["Employer"].signed_amount
  end

  test "publishes entries onto the selected account with mapped categories and tags, plus opening balance" do
    import = qif_import(file_fixture("imports/transactions.qif").read, account: @account)
    import.generate_rows_from_csv
    import.reload.sync_mappings

    # Aceita todas as categorias e tags "como novas"
    import.mappings.categories.each { |m| m.update!(create_when_empty: true) }
    import.mappings.tags.each { |m| m.update!(create_when_empty: true) }

    # 4 transacoes + 1 ancora de saldo inicial (Valuation) = 5 Entries
    assert_difference -> { Entry.count } => 5, -> { Transaction.count } => 4, -> { Valuation.count } => 1 do
      import.publish
    end

    assert_equal "complete", import.status

    entries = import.entries.reload
    landlord = entries.find { |e| e.name == "Landlord" }
    employer = entries.find { |e| e.name == "Employer" }

    assert_equal BigDecimal("1500.00"), landlord.amount   # despesa positiva
    assert_equal BigDecimal("-3200.00"), employer.amount  # receita negativa

    # Categorias criadas e associadas
    assert_equal "Housing", landlord.entryable.category.name

    # Saldo inicial ancorado a partir do registro "Opening Balance"
    manager = Account::OpeningBalanceManager.new(@account.reload)
    assert manager.has_opening_anchor?
    assert_equal BigDecimal("2500.00"), manager.opening_balance
    assert_equal Date.new(2024, 1, 2), manager.opening_date
  end

  private
    def rows_by_name(import)
      import.rows.reload.index_by(&:name)
    end

    def qif_import(content, account: nil)
      @family.imports.create!(
        type:         "QifImport",
        account:      account,
        raw_file_str: content
      )
    end
end
