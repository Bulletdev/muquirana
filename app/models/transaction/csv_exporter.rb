# Gera um CSV plano (uma linha por transacao) a partir de um escopo de
# transacoes da familia. Feito para ser puxado direto no Google Sheets via
# IMPORTDATA, por isso os valores monetarios vao como numero cru (sem simbolo
# de moeda nem separador de milhar), com a moeda em coluna propria.
class Transaction::CsvExporter
  # Colunas do CSV. Os rotulos sao traduzidos (pt-BR/en) via I18n no cabecalho.
  COLUMNS = %i[date name amount currency type category merchant account tags notes].freeze

  def initialize(transactions_scope, family:)
    @scope = transactions_scope
    @family = family
  end

  def filename
    "muquirana_transactions_#{Date.current.strftime('%Y%m%d')}.csv"
  end

  def generate
    require "csv"

    CSV.generate do |csv|
      csv << COLUMNS.map { |col| I18n.t("reports.export.columns.#{col}") }

      rows.each { |transaction| csv << row_for(transaction) }
    end
  end

  private
    attr_reader :scope, :family

    def rows
      scope
        .reverse_chronological
        .includes({ entry: :account }, :category, :merchant, :tags)
    end

    def row_for(transaction)
      entry = transaction.entry

      [
        entry.date.iso8601,
        entry.name,
        # Valor cru: negativo = entrada (income), positivo = saida (expense),
        # seguindo a convencao de sinal do Entry.
        format("%.2f", entry.amount),
        entry.currency,
        I18n.t("reports.export.types.#{entry.classification}"),
        transaction.category&.name,
        transaction.merchant&.name,
        entry.account.name,
        transaction.tags.map(&:name).join(", "),
        entry.notes
      ]
    end
end
