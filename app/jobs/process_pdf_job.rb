# frozen_string_literal: true

# Processa uma importacao por PDF em background: classifica o documento via IA,
# e - se for extrato/fatura - extrai os lancamentos e gera os import_rows.
#
# Ao final, extratos/faturas com linhas geradas ficam em `pending` para o
# usuario revisar e publicar; outros tipos de documento sao marcados `complete`
# (nao ha lancamentos a importar).
class ProcessPdfJob < ApplicationJob
  queue_as :medium_priority

  def perform(pdf_import)
    return unless pdf_import.is_a?(PdfImport)
    return reset_processing_claim(pdf_import) unless pdf_import.pdf_uploaded?
    return if pdf_import.status == "complete"
    return reset_processing_claim(pdf_import) if pdf_import.ai_processed? && (!pdf_import.statement_with_transactions? || pdf_import.rows.any?)

    pdf_import.update!(status: :importing)

    begin
      process_result = pdf_import.process_with_ai
      document_type = resolve_document_type(pdf_import, process_result)

      if statement_with_transactions?(document_type)
        pdf_import.extract_transactions
        pdf_import.generate_rows_from_extracted_data
        pdf_import.sync_mappings
        Rails.logger.info("ProcessPdfJob: geradas #{pdf_import.rows.count} linhas para import #{pdf_import.id}")
      end

      final_status = statement_with_transactions?(document_type) && pdf_import.rows.any? ? :pending : :complete
      pdf_import.update!(status: final_status)
    rescue StandardError => e
      sanitized_error = sanitize_error_message(e)
      Rails.logger.error("Processamento de PDF falhou (import #{pdf_import.id}): #{e.class.name} - #{sanitized_error}")
      begin
        pdf_import.update!(status: :failed, error: sanitized_error)
      rescue StandardError => update_error
        Rails.logger.error("Falha ao atualizar status da importacao: #{update_error.message}")
      end
      raise
    end
  end

  private
    def sanitize_error_message(error)
      case error
      when RuntimeError, ArgumentError
        I18n.t("imports.pdf_import.processing_failed_with_message", message: error.message.truncate(500))
      else
        I18n.t("imports.pdf_import.processing_failed_generic", error: error.class.name.demodulize)
      end
    end

    def resolve_document_type(pdf_import, process_result)
      return process_result.document_type if process_result.respond_to?(:document_type) && process_result.document_type.present?

      pdf_import.reload.document_type
    end

    def statement_with_transactions?(document_type)
      document_type.in?(%w[bank_statement credit_card_statement])
    end

    def reset_processing_claim(pdf_import)
      pdf_import.with_lock do
        pdf_import.update!(status: :pending) if pdf_import.importing? && pdf_import.updated_at <= 30.minutes.ago
      end
    end
end
