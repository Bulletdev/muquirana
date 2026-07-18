class Import < ApplicationRecord
  MaxRowCountExceededError = Class.new(StandardError)

  TYPES = %w[TransactionImport TradeImport AccountImport MintImport YnabImport ActualImport QifImport OfxImport PdfImport].freeze

  # Tipos de documento que a IA sabe classificar (importacao por PDF).
  DOCUMENT_TYPES = %w[bank_statement credit_card_statement investment_statement financial_document contract other].freeze
  SIGNAGE_CONVENTIONS = %w[inflows_positive inflows_negative]
  SEPARATORS = [ [ "Comma (,)", "," ], [ "Semicolon (;)", ";" ] ].freeze

  NUMBER_FORMATS = {
    "1,234.56" => { separator: ".", delimiter: "," },  # US/UK/Asia
    "1.234,56" => { separator: ",", delimiter: "." },  # Most of Europe
    "1 234,56" => { separator: ",", delimiter: " " },  # French/Scandinavian
    "1,234"    => { separator: "",  delimiter: "," }   # Zero-decimal currencies like JPY
  }.freeze

  AMOUNT_TYPE_STRATEGIES = %w[signed_amount custom_column].freeze

  belongs_to :family
  belongs_to :account, optional: true

  before_validation :set_default_number_format
  before_validation :ensure_utf8_encoding
  before_save :ensure_utf8_encoding

  scope :ordered, -> { order(created_at: :desc) }

  enum :status, {
    pending: "pending",
    complete: "complete",
    importing: "importing",
    reverting: "reverting",
    revert_failed: "revert_failed",
    failed: "failed"
  }, validate: true, default: "pending"

  validates :type, inclusion: { in: TYPES }
  validates :amount_type_strategy, inclusion: { in: AMOUNT_TYPE_STRATEGIES }
  validates :col_sep, inclusion: { in: SEPARATORS.map(&:last) }
  validates :signage_convention, inclusion: { in: SIGNAGE_CONVENTIONS }, allow_nil: true
  validates :number_format, presence: true, inclusion: { in: NUMBER_FORMATS.keys }

  has_many :rows, dependent: :destroy
  has_many :mappings, dependent: :destroy
  has_many :accounts, dependent: :destroy
  has_many :entries, dependent: :destroy

  class << self
    def parse_csv_str(csv_str, col_sep: ",")
      CSV.parse(
        (csv_str || "").strip,
        headers: true,
        col_sep: col_sep,
        converters: [ ->(str) { str&.strip } ],
        liberal_parsing: true
      )
    end

    # Faixa de datas considerada "plausivel" para um extrato financeiro. Usada
    # para desempatar a deteccao automatica de formato de data (US x pt-BR etc.).
    def reasonable_date_range
      Date.new(1970, 1, 1)..Date.today.next_year(5)
    end

    # Detecta o formato de data (strptime) que melhor explica uma amostra de
    # strings de data. Pontua cada candidato pelo numero de amostras que parseia
    # e, como desempate, quantas caem numa faixa plausivel. Retorna +fallback+
    # quando nada parseia. Necessario para os importadores de formato dedicado
    # (QIF/OFX) que nao passam pela tela de configuracao de coluna.
    def detect_date_format(samples, candidates: Family::DATE_FORMATS.map(&:last), fallback: "%Y-%m-%d")
      cleaned = Array(samples).map(&:to_s).reject(&:blank?).uniq.first(50)
      return fallback if cleaned.empty?

      range = reasonable_date_range

      scored = candidates.map do |fmt|
        parsed = 0
        reasonable = 0

        cleaned.each do |s|
          date = begin
            Date.strptime(s, fmt)
          rescue Date::Error, ArgumentError
            nil
          end
          next unless date

          parsed += 1
          reasonable += 1 if range.cover?(date)
        end

        { format: fmt, parsed: parsed, reasonable: reasonable }
      end

      viable = scored.select { |s| s[:parsed] > 0 }
      return fallback if viable.empty?

      viable.max_by { |s| [ s[:parsed], s[:reasonable] ] }[:format]
    end
  end

  # A maioria dos importadores segue o fluxo CSV (upload -> configuracao de
  # colunas -> limpeza -> mapeamento). Formatos dedicados (QIF/OFX) tem estrutura
  # fixa e sobrescrevem isto para pular a etapa de configuracao de coluna.
  def requires_csv_workflow?
    true
  end

  def publish_later
    raise MaxRowCountExceededError if row_count_exceeded?
    raise "Import is not publishable" unless publishable?

    update! status: :importing

    ImportJob.perform_later(self)
  end

  def publish
    raise MaxRowCountExceededError if row_count_exceeded?

    import!

    family.sync_later

    update! status: :complete
  rescue => error
    update! status: :failed, error: error.message
  end

  def revert_later
    raise "Import is not revertable" unless revertable?

    update! status: :reverting

    RevertImportJob.perform_later(self)
  end

  def revert
    Import.transaction do
      accounts.destroy_all
      entries.destroy_all
    end

    family.sync_later

    update! status: :pending
  rescue => error
    update! status: :revert_failed, error: error.message
  end

  def csv_rows
    @csv_rows ||= parsed_csv
  end

  def csv_headers
    parsed_csv.headers
  end

  def csv_sample
    @csv_sample ||= parsed_csv.first(2)
  end

  def dry_run
    mappings = {
      transactions: rows.count,
      categories: Import::CategoryMapping.for_import(self).creational.count,
      tags: Import::TagMapping.for_import(self).creational.count
    }

    mappings.merge(
      accounts: Import::AccountMapping.for_import(self).creational.count,
    ) if account.nil?

    mappings
  end

  def required_column_keys
    []
  end

  def column_keys
    raise NotImplementedError, "Subclass must implement column_keys"
  end

  def generate_rows_from_csv
    rows.destroy_all

    mapped_rows = csv_rows.map do |row|
      {
        account: row[account_col_label].to_s,
        date: row[date_col_label].to_s,
        qty: sanitize_number(row[qty_col_label]).to_s,
        ticker: row[ticker_col_label].to_s,
        exchange_operating_mic: row[exchange_operating_mic_col_label].to_s,
        price: sanitize_number(row[price_col_label]).to_s,
        amount: sanitize_number(row[amount_col_label]).to_s,
        currency: (row[currency_col_label] || default_currency).to_s,
        name: (row[name_col_label] || default_row_name).to_s,
        category: row[category_col_label].to_s,
        tags: row[tags_col_label].to_s,
        entity_type: row[entity_type_col_label].to_s,
        notes: row[notes_col_label].to_s
      }
    end

    rows.insert_all!(mapped_rows)
  end

  def sync_mappings
    transaction do
      mapping_steps.each do |mapping_class|
        mappables_by_key = mapping_class.mappables_by_key(self)

        updated_mappings = mappables_by_key.map do |key, mappable|
          mapping = mappings.find_or_initialize_by(key: key, import: self, type: mapping_class.name)
          mapping.mappable = mappable
          mapping.create_when_empty = key.present? && mappable.nil?
          mapping
        end

        updated_mappings.each { |m| m.save(validate: false) }
        mapping_class.where.not(id: updated_mappings.map(&:id)).destroy_all
      end
    end
  end

  def mapping_steps
    []
  end

  def uploaded?
    raw_file_str.present?
  end

  def configured?
    uploaded? && rows.any?
  end

  def cleaned?
    configured? && rows.all?(&:valid?)
  end

  def publishable?
    cleaned? && mappings.all?(&:valid?)
  end

  def revertable?
    complete? || revert_failed?
  end

  def has_unassigned_account?
    mappings.accounts.where(key: "").any?
  end

  def requires_account?
    family.accounts.empty? && has_unassigned_account?
  end

  # Used to optionally pre-fill the configuration for the current import
  def suggested_template
    family.imports
          .complete
          .where(account: account, type: type)
          .order(created_at: :desc)
          .first
  end

  def apply_template!(import_template)
    update!(
      import_template.attributes.slice(
        "date_col_label", "amount_col_label", "name_col_label",
        "category_col_label", "tags_col_label", "account_col_label",
        "qty_col_label", "ticker_col_label", "price_col_label",
        "entity_type_col_label", "notes_col_label", "currency_col_label",
        "date_format", "signage_convention", "number_format",
        "exchange_operating_mic_col_label"
      )
    )
  end

  def max_row_count
    10000
  end

  private
    def row_count_exceeded?
      rows.count > max_row_count
    end

    def import!
      # no-op, subclasses can implement for customization of algorithm
    end

    def default_row_name
      "Imported item"
    end

    def default_currency
      family.currency
    end

    def parsed_csv
      @parsed_csv ||= self.class.parse_csv_str(raw_file_str, col_sep: col_sep)
    end

    def sanitize_number(value)
      return "" if value.nil?

      format = NUMBER_FORMATS[number_format]
      return "" unless format

      # First, normalize spaces and remove any characters that aren't numbers, delimiters, separators, or minus signs
      sanitized = value.to_s.strip

      # Handle French/Scandinavian format specially
      if format[:delimiter] == " "
        sanitized = sanitized.gsub(/\s+/, "") # Remove all spaces first
      else
        sanitized = sanitized.gsub(/[^\d#{Regexp.escape(format[:delimiter])}#{Regexp.escape(format[:separator])}\-]/, "")

        # Replace delimiter with empty string
        if format[:delimiter].present?
          sanitized = sanitized.gsub(format[:delimiter], "")
        end
      end

      # Replace separator with period for proper float parsing
      if format[:separator].present?
        sanitized = sanitized.gsub(format[:separator], ".")
      end

      # Return empty string if not a valid number
      unless sanitized =~ /\A-?\d+\.?\d*\z/
        return ""
      end

      sanitized
    end

    # O default do upstream era "1,234.56" (US/UK). Num app pt-BR isso fazia a
    # importacao interpretar errado o CSV que o usuario naturalmente exporta do
    # banco brasileiro: "1.234,56" viraria 1.23456 em vez de 1234.56.
    #
    # E so o valor inicial -- o usuario escolhe outro formato na tela de
    # configuracao da importacao, e as chaves de NUMBER_FORMATS continuam
    # identificadores persistidos.
    def set_default_number_format
      self.number_format ||= "1.234,56"
    end

    # Encodings testados quando a deteccao automatica falha ou fica sob o limiar
    # de confianca. ISO-8859-1/Windows-1252 vem primeiro porque extratos de banco
    # brasileiro tipicamente sao exportados em Latin-1.
    COMMON_ENCODINGS = [ "ISO-8859-1", "Windows-1252", "Windows-1250", "ISO-8859-2" ].freeze

    # rchardet e excelente para separar UTF-8 de single-byte, mas em textos
    # curtos com acentuacao latina ele as vezes "ve" um alfabeto exotico (ex:
    # hebraico windows-1255) com altissima confianca. Como a Muquirana e pt-BR,
    # so confiamos na deteccao quando ela aponta um encoding plausivel para o
    # nosso publico; do contrario caimos no fallback que assume Latin-1/Win-1252.
    PLAUSIBLE_DETECTED_ENCODINGS = [
      "utf-8", "ascii", "us-ascii", "iso-8859-1", "iso-8859-15", "windows-1252"
    ].freeze

    # Extratos CSV de bancos BR frequentemente vem em Latin-1 (ISO-8859-1) e os
    # acentos quebram no parse ("Ã§" no lugar de "ç"). Detectamos o encoding com
    # rchardet e transcodificamos para UTF-8 ANTES do CSV.parse. Arquivos que ja
    # sao UTF-8 valido passam intactos.
    def ensure_utf8_encoding
      # Ignora nil/vazio antes de qualquer checagem de mudanca
      return if raw_file_str.nil? || raw_file_str.bytesize == 0

      # So processa quando o conteudo do arquivo mudou
      return unless will_save_change_to_raw_file_str?

      # Ja e UTF-8 valido: nada a fazer
      begin
        return if raw_file_str.encoding == Encoding::UTF_8 && raw_file_str.valid_encoding?
      rescue ArgumentError
        # encoding invalido no proprio objeto -- segue para deteccao
      end

      begin
        require "rchardet"
        detection = CharDet.detect(raw_file_str)
        detected_encoding = detection["encoding"]
        confidence = detection["confidence"]

        plausible = detected_encoding &&
                    PLAUSIBLE_DETECTED_ENCODINGS.include?(detected_encoding.downcase)

        if plausible && confidence && confidence > 0.75
          self.raw_file_str = raw_file_str
            .force_encoding(detected_encoding)
            .encode("UTF-8", invalid: :replace, undef: :replace)
        else
          # Deteccao fraca ou implausivel para o publico BR: tenta os comuns
          try_common_encodings
        end
      rescue LoadError
        # rchardet indisponivel: fallback seguro
        try_common_encodings
      rescue ArgumentError, Encoding::CompatibilityError
        try_common_encodings
      end
    end

    def try_common_encodings
      COMMON_ENCODINGS.each do |encoding|
        begin
          candidate = raw_file_str.dup.force_encoding(encoding)
          if candidate.valid_encoding?
            self.raw_file_str = candidate.encode("UTF-8", invalid: :replace, undef: :replace)
            return
          end
        rescue Encoding::InvalidByteSequenceError, Encoding::UndefinedConversionError
          next
        end
      end

      # Ultimo recurso: forca UTF-8 e substitui bytes invalidos
      self.raw_file_str = raw_file_str.force_encoding("UTF-8").scrub("?")
    end
end
