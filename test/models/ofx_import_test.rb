require "test_helper"

class OfxImportTest < ActiveSupport::TestCase
  setup do
    @family  = families(:dylan_family)
    @account = accounts(:depository)
  end

  test "default config is applied after create" do
    import = @family.imports.create!(type: "OfxImport")

    assert_equal "inflows_positive", import.signage_convention
    assert_equal "%Y-%m-%d", import.date_format
    assert_equal "1,234.56", import.number_format
    assert_not import.requires_csv_workflow?
    assert_empty import.mapping_steps
  end

  test "parses transactions from a real SGML (OFX 1.x) BR bank fixture" do
    import = ofx_import(file_fixture("imports/statement.ofx").read)
    import.generate_rows_from_csv

    # 5 STMTTRN no arquivo, mas dois compartilham o mesmo FITID -> 4 apos dedup
    assert_equal 4, import.rows.count

    by_fitid = import.rows.reload.index_by(&:entity_type)

    rent = by_fitid["20240103001"]
    assert_equal "2024-01-03", rent.date
    assert_equal BigDecimal("-1500.00"), rent.amount.to_d
    assert_equal "ALUGUEL JANEIRO", rent.name

    coffee = by_fitid["20240105001"]
    # NAME preenchido -> vira o nome; MEMO diferente -> vira nota
    assert_equal "CAFETERIA CENTRAL", coffee.name
    assert_equal "COMPRA CARTAO DEBITO", coffee.notes

    salary = by_fitid["20240110001"]
    assert_equal BigDecimal("3200.00"), salary.amount.to_d
    assert_equal "SALARIO MENSAL", salary.name
  end

  test "deduplicates transactions by FITID" do
    import = ofx_import(file_fixture("imports/statement.ofx").read)
    import.generate_rows_from_csv

    fitids = import.rows.reload.map(&:entity_type)
    assert_equal fitids.uniq, fitids
    assert_equal 1, fitids.count("20240115001")
  end

  test "parses the ledger balance and account data" do
    import   = ofx_import(file_fixture("imports/statement.ofx").read)
    balance  = OfxParser.parse_balance(import.raw_file_str)
    account  = OfxParser.parse_account(import.raw_file_str)

    assert_equal BigDecimal("2068.60"), balance.amount
    assert_equal Date.new(2024, 1, 31), balance.date

    assert_equal "341", account.bank_id
    assert_equal "12345-6", account.account_id
    assert_equal "CHECKING", account.account_type
  end

  test "signage: debits become positive, credits negative in the internal convention" do
    import = ofx_import(file_fixture("imports/statement.ofx").read)
    import.generate_rows_from_csv

    by_fitid = import.rows.reload.index_by(&:entity_type)

    # Debito (TRNAMT negativo) -> despesa positiva na convencao interna
    assert_equal BigDecimal("1500.00"), by_fitid["20240103001"].signed_amount
    # Credito (TRNAMT positivo) -> receita negativa na convencao interna
    assert_equal BigDecimal("-3200.00"), by_fitid["20240110001"].signed_amount
  end

  test "handles OFX 2.x XML with closed tags" do
    xml = <<~OFX
      <?xml version="1.0" encoding="UTF-8"?>
      <?OFX OFXHEADER="200" VERSION="211" SECURITY="NONE" OLDFILEUID="NONE" NEWFILEUID="NONE"?>
      <OFX>
        <BANKMSGSRSV1>
          <STMTTRNRS>
            <STMTRS>
              <CURDEF>BRL</CURDEF>
              <BANKACCTFROM>
                <BANKID>001</BANKID>
                <ACCTID>98765-4</ACCTID>
                <ACCTTYPE>CHECKING</ACCTTYPE>
              </BANKACCTFROM>
              <BANKTRANLIST>
                <STMTTRN>
                  <TRNTYPE>DEBIT</TRNTYPE>
                  <DTPOSTED>20240220120000</DTPOSTED>
                  <TRNAMT>-99.90</TRNAMT>
                  <FITID>XML001</FITID>
                  <MEMO>ASSINATURA STREAMING</MEMO>
                </STMTTRN>
              </BANKTRANLIST>
              <LEDGERBAL>
                <BALAMT>400.10</BALAMT>
                <DTASOF>20240229120000</DTASOF>
              </LEDGERBAL>
            </STMTRS>
          </STMTTRNRS>
        </BANKMSGSRSV1>
      </OFX>
    OFX

    import = ofx_import(xml)
    import.generate_rows_from_csv

    row = import.rows.reload.sole
    assert_equal "2024-02-20", row.date
    assert_equal BigDecimal("-99.90"), row.amount.to_d
    assert_equal "ASSINATURA STREAMING", row.name
    assert_equal "XML001", row.entity_type
  end

  test "publishes entries onto the selected account and anchors the opening balance from LEDGERBAL" do
    import = ofx_import(file_fixture("imports/statement.ofx").read, account: @account)
    import.generate_rows_from_csv

    # 4 transacoes + 1 ancora de saldo inicial (Valuation) = 5 Entries
    assert_difference -> { Entry.count } => 5, -> { Transaction.count } => 4, -> { Valuation.count } => 1 do
      import.publish
    end

    assert_equal "complete", import.status

    entries  = import.entries.reload
    assert_equal BigDecimal("1500.00"), entries.find { |e| e.name == "ALUGUEL JANEIRO" }.amount
    assert_equal BigDecimal("-3200.00"), entries.find { |e| e.name == "SALARIO MENSAL" }.amount

    # opening = LEDGERBAL 2068.60 - movimento liquido 1568.60 = 500.00
    manager = Account::OpeningBalanceManager.new(@account.reload)
    assert manager.has_opening_anchor?
    assert_equal BigDecimal("500.00"), manager.opening_balance
    assert_equal Date.new(2024, 1, 2), manager.opening_date  # dia anterior a transacao mais antiga
  end

  private
    def ofx_import(content, account: nil)
      @family.imports.create!(
        type:         "OfxImport",
        account:      account,
        raw_file_str: content
      )
    end
end
