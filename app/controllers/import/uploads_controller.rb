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
    if @import.is_a?(QifImport)
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
      params.require(:import).permit(:raw_file_str, :csv_file, :col_sep)
    end
end
