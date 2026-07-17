# frozen_string_literal: true

# Importacao de extrato/fatura em PDF via IA (caminho OpenAI).
#
# Fluxo: upload -> classifica o documento via LLM -> extrai os lancamentos via
# LLM -> gera import_rows -> mapeia categoria -> publica (cria Entries).
#
# Diferente dos importadores CSV/OFX/QIF, o PDF nao tem estrutura fixa: o
# conteudo e texto livre que a IA precisa interpretar. Por isso o
# processamento roda em background (ProcessPdfJob) e nao ha etapa de
# configuracao de colunas (`requires_csv_workflow? == false`).
class PdfImport < Import
  belongs_to :account_statement, optional: true

  validates :document_type, inclusion: { in: DOCUMENT_TYPES }, allow_nil: true

  class << self
    # Cria (ou reaproveita) uma importacao a partir de um PDF enviado. Deduplica
    # pelo hash do conteudo: subir o mesmo arquivo de novo nao reprocessa.
    def create_from_upload!(family:, file:, account: nil)
      statement = AccountStatement.create_from_upload!(family: family, file: file, account: account)
      create_from_statement!(statement: statement, account: account)
    rescue AccountStatement::DuplicateUploadError => e
      create_from_statement!(statement: e.statement, account: account)
    end

    def create_from_statement!(statement:, account: nil)
      reusable = statement.pdf_imports.where.not(status: :failed).ordered.first
      return reusable if reusable

      create!(
        family: statement.family,
        account: account || statement.account,
        account_statement: statement,
        date_format: statement.family.date_format,
        status: :pending
      )
    end
  end

  # ------------------------------------------------------------------
  # Processamento por IA
  # ------------------------------------------------------------------

  # Enfileira o processamento em background, protegendo com lock de status para
  # nao disparar dois jobs para a mesma importacao.
  def process_with_ai_later
    return false unless with_lock { pending? && !ai_processed? && rows.none? && pdf_uploaded? && update!(status: :importing) }

    begin
      ProcessPdfJob.perform_later(self)
      true
    rescue StandardError => e
      Rails.logger.error("Falha ao enfileirar processamento de PDF (import #{id}): #{e.class.name} - #{e.message}")
      reload.with_lock { update!(status: :pending) }
      false
    end
  end

  # Classifica o documento (tipo + resumo) via LLM.
  def process_with_ai
    provider = llm_provider
    raise "Provedor de IA nao configurado" unless provider
    raise "Provedor de IA nao suporta processamento de PDF" unless provider.supports_pdf_processing?

    response = provider.process_pdf(pdf_content: pdf_file_content, family: family)
    raise(response.error&.message || "Erro desconhecido ao processar o PDF") unless response.success?

    result = response.data
    update!(ai_summary: result.summary, document_type: result.document_type)
    result
  end

  # Extrai os lancamentos do extrato/fatura via LLM e guarda em extracted_data.
  def extract_transactions
    return unless statement_with_transactions?

    provider = llm_provider
    raise "Provedor de IA nao configurado" unless provider

    response = provider.extract_bank_statement(pdf_content: pdf_file_content, family: family)
    raise(response.error&.message || "Erro desconhecido na extracao") unless response.success?

    update!(extracted_data: response.data.deep_stringify_keys)
    extracted_data
  end

  # Transforma os lancamentos extraidos em Import::Row (mesma estrutura dos
  # importadores CSV, para reaproveitar a etapa de limpeza/mapeamento).
  def generate_rows_from_extracted_data
    transaction do
      rows.destroy_all
      return unless has_extracted_transactions?

      currency = account&.currency || family.currency

      mapped_rows = extracted_transactions.map do |txn|
        {
          date: format_date_for_import(txn["date"]),
          amount: txn["amount"].to_s,
          name: txn["name"].to_s.presence || default_row_name,
          category: txn["category"].to_s,
          notes: txn["notes"].to_s,
          currency: currency.to_s,
          tags: "",
          account: "",
          qty: "",
          ticker: "",
          price: "",
          entity_type: ""
        }
      end

      rows.insert_all!(mapped_rows) if mapped_rows.any?
      rows.reset
    end
  end

  # ------------------------------------------------------------------
  # Publicacao (cria Entries)
  # ------------------------------------------------------------------

  def import!
    raise "Conta obrigatoria para importar PDF" unless account.present?

    transaction do
      mappings.each(&:create_mappable!)

      entries = rows.map do |row|
        category = mappings.categories.mappable_for(row.category)

        Transaction.new(
          category: category,
          entry: Entry.new(
            account: account,
            date: row.date_iso,
            amount: row.signed_amount,
            name: row.name,
            currency: row.currency,
            notes: row.notes,
            import: self
          )
        )
      end

      Transaction.import!(entries, recursive: true) if entries.any?
    end
  end

  # ------------------------------------------------------------------
  # Estado / consultas
  # ------------------------------------------------------------------

  def requires_csv_workflow?
    false
  end

  def column_keys
    %i[date amount name category notes]
  end

  def required_column_keys
    %i[date amount]
  end

  def mapping_steps
    return [] unless rows.where.not(category: [ nil, "" ]).exists?

    [ Import::CategoryMapping ]
  end

  def pdf_uploaded?
    account_statement&.original_file&.attached? || false
  end

  def uploaded?
    pdf_uploaded?
  end

  def ai_processed?
    ai_summary.present?
  end

  def configured?
    uploaded? && rows.any?
  end

  def publishable?
    account.present? && statement_with_transactions? && cleaned? && mappings.all?(&:valid?)
  end

  def bank_statement?
    document_type == "bank_statement"
  end

  def statement_with_transactions?
    document_type.in?(%w[bank_statement credit_card_statement])
  end

  def has_extracted_transactions?
    extracted_transactions.present?
  end

  def extracted_transactions
    extracted_data&.dig("transactions") || []
  end

  def pdf_file_content
    @pdf_file_content ||= account_statement&.original_file_content
  end

  def pdf_filename
    account_statement&.filename
  end

  private
    def llm_provider
      Provider::Registry.get_provider(:openai)
    end

    def format_date_for_import(date_str)
      return "" if date_str.blank?

      Date.parse(date_str).strftime(date_format)
    rescue ArgumentError, Date::Error
      date_str.to_s
    end
end
