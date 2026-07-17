class YnabImport < Import
  after_create :set_mappings

  DEFAULT_COLUMN_MAPPINGS = {
    signage_convention: "inflows_positive",
    date_col_label: "Date",
    date_format: "%m/%d/%Y",
    name_col_label: "Payee",
    account_col_label: "Account",
    category_col_label: "Category",
    notes_col_label: "Memo"
  }.freeze

  # Exports do YNAB sempre usam estes cabecalhos literais; eles nao aparecem como
  # colunas remapeaveis porque o valor e a categoria sao derivados deles.
  OUTFLOW_COLUMN = "Outflow".freeze
  INFLOW_COLUMN = "Inflow".freeze
  # O YNAB moderno (web) traz uma coluna ja combinada mais o par grupo/folha.
  COMBINED_CATEGORY_COLUMN = "Category Group/Category".freeze
  CATEGORY_GROUP_COLUMN = "Category Group".freeze
  # O YNAB 4 (classico/legado) separa a categoria de outra forma.
  MASTER_CATEGORY_COLUMN = "Master Category".freeze
  SUB_CATEGORY_COLUMN = "Sub Category".freeze

  def self.default_column_mappings
    DEFAULT_COLUMN_MAPPINGS
  end

  def generate_rows_from_csv
    rows.destroy_all

    mapped_rows = csv_rows.map do |row|
      {
        account: csv_value(row, account_col_label, "account", "account_name").to_s,
        date: csv_value(row, date_col_label, "date").to_s,
        amount: signed_csv_amount(row).to_s,
        currency: default_currency.to_s,
        name: row_name(row),
        category: combined_category(row),
        notes: csv_value(row, notes_col_label, "notes", "memo").to_s
      }
    end

    rows.insert_all!(mapped_rows)
  end

  def import!
    transaction do
      mappings.each(&:create_mappable!)

      rows.each do |row|
        account = mappings.accounts.mappable_for(row.account)
        category = mappings.categories.mappable_for(row.category)

        entry = account.entries.build \
          date: row.date_iso,
          amount: row.signed_amount,
          name: row.name,
          currency: row.currency,
          notes: row.notes,
          entryable: Transaction.new(category: category),
          import: self

        entry.save!
      end
    end
  end

  def mapping_steps
    [ Import::CategoryMapping, Import::AccountMapping ]
  end

  def required_column_keys
    %i[date amount]
  end

  def column_keys
    %i[date name category account notes]
  end

  def csv_template
    template = <<~CSV
      Account,Flag,Date,Payee,Category Group/Category,Category Group,Category,Memo,Outflow,Inflow,Cleared
      Checking,,01/01/2024,Employer,Income: Paycheck,Income,Paycheck,Monthly salary,$0.00,$2500.00,Cleared
      Credit Card,,01/03/2024,Coffee Shop,Dining Out: Coffee,Dining Out,Coffee,Morning coffee,$4.25,$0.00,Uncleared
    CSV

    CSV.parse(template, headers: true)
  end

  # O YNAB divide a movimentacao entre as colunas Outflow e Inflow (magnitudes
  # positivas) em vez de um unico valor com sinal. Combinamos as duas na convencao
  # "inflows positive" que o framework espera - o Import::Row depois inverte para a
  # convencao interna "outflows positive". Uma coluna Amount unica, se presente,
  # tem prioridade (alguns exports feitos a mao usam uma so).
  def signed_csv_amount(csv_row)
    explicit = csv_value(csv_row, amount_col_label.presence || "Amount")
    return sanitize_number(explicit).to_d if explicit.present?

    # Se o arquivo nao expoe nenhuma origem de valor reconhecivel (arquivo errado
    # ou cabecalhos renomeados), deixamos o valor em branco para que a validacao de
    # coluna obrigatoria bloqueie a importacao em vez de criar lancamentos zerados.
    return nil unless amount_source_columns?

    inflow  = sanitize_number(csv_value(csv_row, INFLOW_COLUMN)).to_d
    outflow = sanitize_number(csv_value(csv_row, OUTFLOW_COLUMN)).to_d

    inflow - outflow.abs
  end

  private
    def set_mappings
      assign_attributes(self.class.default_column_mappings)
      save!
    end

    # Verdadeiro quando o arquivo enviado tem pelo menos uma coluna da qual o valor
    # pode ser derivado: Outflow, Inflow ou um unico Amount com sinal.
    def amount_source_columns?
      header_for(OUTFLOW_COLUMN).present? ||
        header_for(INFLOW_COLUMN).present? ||
        header_for(amount_col_label.presence || "Amount").present?
    end

    # O YNAB exporta linhas de saldo inicial / reconciliacao com o Payee em branco.
    # O Entry exige um nome, entao caimos no Memo e por fim no default generico,
    # espelhando o tratamento de nome em branco do Import e do MintImport.
    def row_name(row)
      csv_value(row, name_col_label, "payee").to_s.presence ||
        csv_value(row, notes_col_label, "memo").to_s.presence ||
        default_row_name
    end

    # Resolve uma unica string de categoria entre os formatos de export do YNAB:
    #   - YNAB web moderno: coluna ja combinada "Category Group/Category"
    #   - YNAB web moderno (separado): "Category Group" + "Category"
    #   - YNAB 4 legado: "Master Category" + "Sub Category"
    #   - exports simplificados: uma unica coluna "Category" ja com o valor completo
    def combined_category(row)
      combined = csv_value(row, COMBINED_CATEGORY_COLUMN)
      return combined.to_s.strip if combined.present?

      group = csv_value(row, CATEGORY_GROUP_COLUMN).to_s.strip
      return join_category(group, csv_value(row, category_col_label, "category")) if group.present?

      master = csv_value(row, MASTER_CATEGORY_COLUMN).to_s.strip
      sub = csv_value(row, SUB_CATEGORY_COLUMN).to_s.strip
      return join_category(master, sub) if master.present? || sub.present?

      csv_value(row, category_col_label, "category").to_s.strip
    end

    def join_category(group, category)
      category = category.to_s.strip
      return category if group.blank?
      return group if category.blank?

      "#{group}: #{category}"
    end

    # Le um valor da linha tentando o rotulo mapeado e, em seguida, aliases
    # alternativos (case-insensitive), tolerando variacoes de caixa nos cabecalhos
    # exportados pelo YNAB.
    def csv_value(row, label, *aliases)
      [ label, *aliases ].each do |candidate|
        header = header_for(candidate)
        next if header.blank?

        value = row[header]
        return value if value.present?
      end

      nil
    end

    def header_for(candidate)
      return if candidate.blank?

      csv_headers.find { |header| header.to_s.strip.casecmp?(candidate.to_s.strip) }
    end
end
