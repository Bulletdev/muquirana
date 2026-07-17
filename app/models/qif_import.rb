class QifImport < Import
  after_create :set_default_config

  # O formato de data usado para parsear os campos D do arquivo QIF bruto
  # (ex.: "%m/%d/%Y"). Guardado em column_mappings para nao conflitar com
  # date_format, que e sempre "%Y-%m-%d" porque as linhas do QIF ja guardam a
  # data em ISO 8601 depois de parseada.
  def qif_date_format
    column_mappings&.dig("qif_date_format") || "%m/%d/%Y"
  end

  def qif_date_format=(fmt)
    self.column_mappings = (column_mappings || {}).merge("qif_date_format" => fmt)
  end

  # Parseia o conteudo QIF guardado e cria os Import::Row. Substitui o metodo
  # baseado em CSV da classe base por parsing especifico de QIF.
  #
  # Na primeira execucao (qif_date_format ainda nao definido), detecta o formato
  # de data a partir das amostras dos campos D do arquivo.
  def generate_rows_from_csv
    detect_and_set_qif_date_format! unless column_mappings&.key?("qif_date_format")

    rows.destroy_all
    generate_transaction_rows
  end

  def import!
    transaction do
      mappings.each(&:create_mappable!)

      import_transaction_rows!

      if (ob = QifParser.parse_opening_balance(raw_file_str, date_format: qif_date_format))
        Account::OpeningBalanceManager.new(account).set_opening_balance(
          balance: ob[:amount],
          date:    ob[:date]
        )
      else
        adjust_opening_anchor_if_needed!
      end
    end
  end

  # QIF tem formato fixo - nao precisa da etapa de mapeamento de colunas do CSV.
  def requires_csv_workflow?
    false
  end

  def column_keys
    %i[date amount name category tags notes]
  end

  def publishable?
    account.present? && super
  end

  # O tipo de conta declarado no arquivo QIF (ex.: "CCard", "Bank", "Cash").
  def qif_account_type
    return @qif_account_type if instance_variable_defined?(:@qif_account_type)
    @qif_account_type = raw_file_str.present? ? QifParser.account_type(raw_file_str) : nil
  end

  # Categorias unicas usadas nas linhas (entradas em branco excluidas).
  def row_categories
    rows.map(&:category).reject(&:blank?).uniq.sort
  end

  # Tags unicas usadas nas linhas (entradas em branco excluidas).
  def row_tags
    rows.flat_map(&:tags_list).uniq.reject(&:blank?).sort
  end

  def mapping_steps
    [ Import::CategoryMapping, Import::TagMapping ]
  end

  private
    # ------------------------------------------------------------------
    # Geracao de linhas
    # ------------------------------------------------------------------

    def generate_transaction_rows
      transactions = QifParser.parse(raw_file_str, date_format: qif_date_format)

      mapped_rows = transactions.map do |trn|
        {
          date:        trn.date.to_s,
          amount:      trn.amount.to_s,
          currency:    default_currency.to_s,
          name:        (trn.payee.presence || default_row_name).to_s,
          notes:       trn.memo.to_s,
          category:    trn.category.to_s,
          tags:        trn.tags.join("|"),
          account:     "",
          qty:         "",
          ticker:      "",
          price:       "",
          entity_type: ""
        }
      end

      if mapped_rows.any?
        rows.insert_all!(mapped_rows)
        rows.reset
      end
    end

    # ------------------------------------------------------------------
    # Execucao da importacao
    # ------------------------------------------------------------------

    def import_transaction_rows!
      rows.each do |row|
        category = mappings.categories.mappable_for(row.category)
        tags     = row.tags_list.filter_map { |tag| mappings.tags.mappable_for(tag) }

        entry = account.entries.build \
          date:     row.date_iso,
          amount:   row.signed_amount,
          name:     row.name,
          currency: row.currency,
          notes:    row.notes,
          entryable: Transaction.new(category: category, tags: tags),
          import:   self

        entry.save!
      end
    end

    # ------------------------------------------------------------------
    # Helpers
    # ------------------------------------------------------------------

    def adjust_opening_anchor_if_needed!
      manager = Account::OpeningBalanceManager.new(account)
      return unless manager.has_opening_anchor?

      earliest = earliest_row_date
      return unless earliest.present? && earliest < manager.opening_date

      manager.set_opening_balance(
        balance: manager.opening_balance,
        date:    earliest - 1.day
      )
    end

    def earliest_row_date
      str = rows.map(&:date).reject(&:blank?).min
      Date.parse(str) if str.present?
    end

    def set_default_config
      update!(
        signage_convention: "inflows_positive",
        date_format:        "%Y-%m-%d",
        number_format:      "1,234.56"
      )
    end

    # Detecta o formato de data do QIF a partir das amostras dos campos D e o
    # persiste. Cai em "%m/%d/%Y" (convencao US) se a deteccao for inconclusiva.
    def detect_and_set_qif_date_format!
      samples  = QifParser.extract_raw_dates(raw_file_str)
      detected = Import.detect_date_format(samples, fallback: "%m/%d/%Y")
      self.qif_date_format = detected
      update_column(:column_mappings, column_mappings)
    end
end
