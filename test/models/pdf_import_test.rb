require "test_helper"
require "rack/test"

# Fluxo US-12: importacao de extrato/fatura em PDF via IA.
#
# O LLM e SEMPRE stubado - nenhum teste toca a rede nem gasta OpenAI. Duas
# camadas de stub sao usadas:
#   1. Fluxo completo: o provider inteiro (process_pdf / extract_bank_statement)
#      e trocado por um mock que devolve uma extracao "de enlatado".
#   2. Extrator: so o client.chat e o PDF::Reader sao stubados, exercitando o
#      parsing real de datas dd/mm e valores "R$ 1.234,56".
class PdfImportTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @family  = families(:dylan_family)
    @account = accounts(:depository)
  end

  # ------------------------------------------------------------------
  # Helpers
  # ------------------------------------------------------------------

  def pdf_upload
    Rack::Test::UploadedFile.new(file_fixture("imports/statement.pdf").to_s, "application/pdf")
  end

  def classification(document_type: "bank_statement")
    Provider::LlmConcept::PdfProcessingResult.new(
      summary: "Extrato Nubank - janeiro/2024",
      document_type: document_type,
      extracted_data: { "institution_name" => "Nubank", "currency" => "BRL" }
    )
  end

  def extraction_payload
    {
      transactions: [
        { date: "2024-01-05", amount: -45.99,  name: "CAFETERIA CENTRAL", category: nil, notes: "Pix" },
        { date: "2024-01-10", amount: 3200.00, name: "SALARIO",           category: nil, notes: nil }
      ],
      bank_name: "Nubank"
    }
  end

  def stub_llm_provider(document_type: "bank_statement")
    provider = mock("llm_provider")
    provider.stubs(:supports_pdf_processing?).returns(true)
    provider.stubs(:process_pdf).returns(
      Provider::Response.new(success?: true, data: classification(document_type: document_type), error: nil)
    )
    provider.stubs(:extract_bank_statement).returns(
      Provider::Response.new(success?: true, data: extraction_payload, error: nil)
    )
    Provider::Registry.stubs(:get_provider).with(:openai).returns(provider)
    provider
  end

  # ------------------------------------------------------------------
  # Fluxo completo
  # ------------------------------------------------------------------

  test "upload -> IA stubada -> gera import_rows -> publish cria as Entries" do
    stub_llm_provider

    import = PdfImport.create_from_upload!(family: @family, file: pdf_upload, account: @account)

    assert import.pdf_uploaded?
    assert_not import.requires_csv_workflow?
    assert_equal @account, import.account
    assert_equal 1, AccountStatement.where(family: @family).count

    perform_enqueued_jobs do
      assert import.process_with_ai_later, "esperava enfileirar o ProcessPdfJob"
    end

    import.reload
    assert import.ai_processed?
    assert_equal "bank_statement", import.document_type
    assert_equal 2, import.rows.count

    coffee = import.rows.find_by(name: "CAFETERIA CENTRAL")
    assert_equal "-45.99", coffee.amount
    assert_equal Date.new(2024, 1, 5).iso8601, coffee.date_iso
    assert_equal "Pix", coffee.notes

    assert import.publishable?, "esperava publishable, status=#{import.status}"

    assert_difference -> { @account.entries.count }, 2 do
      import.publish
    end

    assert import.reload.complete?

    # Debito -> despesa (positivo na convencao Maybe); credito -> entrada (negativo).
    coffee_entry = @account.entries.find_by(name: "CAFETERIA CENTRAL")
    salary_entry = @account.entries.find_by(name: "SALARIO")
    assert_equal BigDecimal("45.99"),    coffee_entry.amount
    assert_equal BigDecimal("-3200.00"), salary_entry.amount
  end

  test "documento que nao e extrato/fatura: job marca complete e nao gera linhas" do
    stub_llm_provider(document_type: "contract")

    import = PdfImport.create_from_upload!(family: @family, file: pdf_upload, account: @account)

    perform_enqueued_jobs do
      import.process_with_ai_later
    end

    import.reload
    assert import.complete?
    assert_equal "contract", import.document_type
    assert_equal 0, import.rows.count
  end

  # ------------------------------------------------------------------
  # Deduplicacao por hash
  # ------------------------------------------------------------------

  test "dedup por hash: o mesmo PDF nao cria outro statement nem reprocessa" do
    import1 = PdfImport.create_from_upload!(family: @family, file: pdf_upload, account: @account)

    assert_no_difference [ -> { AccountStatement.count }, -> { PdfImport.count } ] do
      import2 = PdfImport.create_from_upload!(family: @family, file: pdf_upload, account: @account)

      assert_equal import1.id, import2.id
      assert_equal import1.account_statement_id, import2.account_statement_id
    end
  end

  test "dedup: AccountStatement.create_from_upload! levanta DuplicateUploadError no segundo upload" do
    AccountStatement.create_from_upload!(family: @family, file: pdf_upload, account: @account)

    error = assert_raises(AccountStatement::DuplicateUploadError) do
      AccountStatement.create_from_upload!(family: @family, file: pdf_upload, account: @account)
    end
    assert error.statement.present?
  end

  # ------------------------------------------------------------------
  # Extrator: parsing BR (datas dd/mm, valores "R$ 1.234,56") - stub do pdf-reader
  # ------------------------------------------------------------------

  test "BankStatementExtractor interpreta valores e datas no padrao brasileiro" do
    fake_page   = mock("page")
    fake_page.stubs(:text).returns("25/12/2024 ALUGUEL -R$ 1.500,00")
    fake_reader = mock("reader")
    fake_reader.stubs(:pages).returns([ fake_page ])
    PDF::Reader.stubs(:new).returns(fake_reader)

    client = mock("openai_client")
    client.stubs(:chat).returns(
      "choices" => [ { "message" => { "content" => {
        "bank_name" => "Itau",
        "transactions" => [
          { "date" => "25/12/2024", "description" => "ALUGUEL",  "amount" => "-1.500,00" },
          { "date" => "10/01/2024", "description" => "SALARIO",  "amount" => 3200.0 },
          { "date" => "11/01/2024", "description" => "MERCADO",  "amount" => "-89,90" }
        ]
      }.to_json } } ]
    )

    result = Provider::Openai::BankStatementExtractor.new(
      client: client, pdf_content: "%PDF-fake", model: "gpt-4.1"
    ).extract

    txns = result[:transactions]
    assert_equal 3, txns.size

    aluguel = txns.find { |t| t[:name] == "ALUGUEL" }
    assert_equal "2024-12-25", aluguel[:date]
    assert_equal(-1500.0, aluguel[:amount])

    mercado = txns.find { |t| t[:name] == "MERCADO" }
    assert_equal(-89.9, mercado[:amount])

    salario = txns.find { |t| t[:name] == "SALARIO" }
    assert_equal 3200.0, salario[:amount]
    assert_equal "Itau", result[:bank_name]
  end

  test "PdfProcessor classifica o documento a partir do texto (client stubado)" do
    fake_page   = mock("page")
    fake_page.stubs(:text).returns("NUBANK - Fatura do cartao - Vencimento 10/02/2024")
    fake_reader = mock("reader")
    fake_reader.stubs(:pages).returns([ fake_page ])
    PDF::Reader.stubs(:new).returns(fake_reader)

    client = mock("openai_client")
    client.stubs(:chat).returns(
      "choices" => [ { "message" => { "content" => {
        "document_type" => "credit_card_statement",
        "summary" => "Fatura Nubank fevereiro/2024",
        "extracted_data" => { "institution_name" => "Nubank" }
      }.to_json } } ]
    )

    result = Provider::Openai::PdfProcessor.new(
      client, model: "gpt-4.1", pdf_content: "%PDF-fake", family: @family
    ).process

    assert_equal "credit_card_statement", result.document_type
    assert_equal "Fatura Nubank fevereiro/2024", result.summary
  end
end
