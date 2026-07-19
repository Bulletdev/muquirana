class Import::UploadsController < ApplicationController
  layout "imports"

  before_action :set_import

  def show
  end

  def sample_csv
    send_data @import.csv_template.to_csv,
      filename: "#{@import.type.underscore.split('_').first}_sample.csv",
      type: "text/csv",
      disposition: "attachment"
  end

  def update
    if @import.is_a?(PdfImport)
      handle_pdf_upload
    elsif @import.is_a?(QifImport)
      handle_dedicated_upload(QifParser, "QIF")
    elsif @import.is_a?(OfxImport)
      handle_dedicated_upload(OfxParser, "OFX")
    elsif csv_valid?(csv_str)
      @import.account = Current.family.accounts.find_by(id: params.dig(:import, :account_id))
      @import.assign_attributes(raw_file_str: csv_str, col_sep: upload_params[:col_sep])
      @import.save!(validate: false)

      redirect_to import_configuration_path(@import, template_hint: true), notice: "CSV uploaded successfully."
    else
      flash.now[:alert] = "Must be valid CSV with headers and at least one row of data"

      render :show, status: :unprocessable_entity
    end
  end

  private
    # Importacao por PDF: exige a conta de destino, guarda o arquivo num
    # AccountStatement (deduplicado por hash) e dispara o processamento por IA em
    # background. As linhas so ficam prontas quando o ProcessPdfJob termina.
    def handle_pdf_upload
      # Chaves absolutas de proposito: este metodo roda na action `update`, entao
      # o lazy `t(".pdf_*")` resolveria para import.uploads.update.* (inexistente).
      # As mensagens vivem em import.uploads.show.* (a view renderizada).
      file = upload_params[:pdf_file] || upload_params[:csv_file]
      unless file.present?
        flash.now[:alert] = t("import.uploads.show.pdf_file_required")
        render :show, status: :unprocessable_entity and return
      end

      account = Current.family.accounts.find_by(id: params.dig(:import, :account_id))
      unless account.present?
        flash.now[:alert] = t("import.uploads.show.pdf_account_required")
        render :show, status: :unprocessable_entity and return
      end

      statement = build_statement_for(file)
      unless statement
        flash.now[:alert] = t("import.uploads.show.pdf_invalid_file")
        render :show, status: :unprocessable_entity and return
      end

      @import.update!(account: account, account_statement: statement, status: :pending)
      @import.process_with_ai_later

      redirect_to import_path(@import), notice: t("import.uploads.show.pdf_processing_started")
    end

    def build_statement_for(file)
      prepared = AccountStatement.prepare_upload!(file)
      AccountStatement.create_from_prepared_upload!(family: Current.family, prepared_upload: prepared)
    rescue AccountStatement::DuplicateUploadError => e
      e.statement
    rescue AccountStatement::InvalidUploadError
      nil
    end

    # QIF e OFX tem formato fixo: em vez de mapear colunas, validamos com o parser
    # dedicado, exigimos a conta de destino e ja geramos as linhas, pulando direto
    # para a etapa de limpeza.
    def handle_dedicated_upload(parser, label)
      unless parser.valid?(csv_str)
        flash.now[:alert] = "Must be a valid #{label} file"
        render :show, status: :unprocessable_entity and return
      end

      account = Current.family.accounts.find_by(id: params.dig(:import, :account_id))
      unless account.present?
        flash.now[:alert] = "Please select an account for the #{label} import"
        render :show, status: :unprocessable_entity and return
      end

      ActiveRecord::Base.transaction do
        @import.account = account
        @import.raw_file_str = parser.normalize_encoding(csv_str)
        @import.save!(validate: false)
        @import.generate_rows_from_csv
        @import.reload.sync_mappings
      end

      redirect_to import_clean_path(@import), notice: "#{label} uploaded successfully."
    end

    def set_import
      @import = Current.family.imports.find(params[:import_id])
    end

    def csv_str
      @csv_str ||= upload_params[:csv_file]&.read || upload_params[:raw_file_str]
    end

    def csv_valid?(str)
      begin
        csv = Import.parse_csv_str(str, col_sep: upload_params[:col_sep])
        return false if csv.headers.empty?
        return false if csv.count == 0
        true
      rescue CSV::MalformedCSVError
        false
      end
    end

    def upload_params
      params.require(:import).permit(:raw_file_str, :csv_file, :pdf_file, :col_sep)
    end
end
