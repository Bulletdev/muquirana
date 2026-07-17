class OfxImport < Import
  after_create :set_default_config

  # Parseia o conteudo OFX guardado e cria os Import::Row. Substitui o metodo
  # baseado em CSV da classe base por parsing especifico de OFX.
  def generate_rows_from_csv
    rows.destroy_all
    generate_transaction_rows
  end

  def import!
    transaction do
      import_transaction_rows!
      apply_ledger_balance_anchor!
    end
  end

  # OFX tem formato fixo - nao precisa da etapa de mapeamento de colunas do CSV.
  def requires_csv_workflow?
    false
  end

  def column_keys
    %i[date amount name notes]
  end

  def publishable?
    account.present? && super
  end

  # OFX nao traz categorias nem tags, entao nao ha etapa de mapeamento.
  def mapping_steps
    []
  end

  # Dados da conta declarados no arquivo (banco, numero, tipo), quando presentes.
  def ofx_account
    return @ofx_account if instance_variable_defined?(:@ofx_account)
    @ofx_account = raw_file_str.present? ? OfxParser.parse_account(raw_file_str) : nil
  end

  private
    # ------------------------------------------------------------------
    # Geracao de linhas
    # ------------------------------------------------------------------

    def generate_transaction_rows
      transactions = deduplicated_transactions

      mapped_rows = transactions.map do |trn|
        {
          date:        trn.date.to_s,
          amount:      trn.amount.to_s,
          currency:    default_currency.to_s,
          name:        row_name(trn),
          notes:       row_notes(trn),
          category:    "",
          tags:        "",
          account:     "",
          qty:         "",
          ticker:      "",
          price:       "",
          # O FITID e o id proprio da transacao no OFX. Guardamos aqui para
          # rastreabilidade e deduplicacao (o CSV nao tem um id equivalente).
          entity_type: trn.fitid.to_s
        }
      end

      if mapped_rows.any?
        rows.insert_all!(mapped_rows)
        rows.reset
      end
    end

    # Remove transacoes com FITID repetido (mantendo a primeira ocorrencia). O
    # FITID e a chave de deduplicacao propria do OFX. Transacoes sem FITID sao
    # sempre mantidas.
    def deduplicated_transactions
      seen = Set.new

      OfxParser.parse(raw_file_str).select do |trn|
        next true if trn.fitid.blank?

        seen.add?(trn.fitid)
      end
    end

    # NAME e o histórico curto/contraparte; MEMO e a descricao longa. Bancos BR
    # costumam preencher so um dos dois, entao caimos de um para o outro e por
    # fim no nome default generico (o Entry exige um nome).
    def row_name(trn)
      trn.name.presence || trn.memo.presence || default_row_name
    end

    # Guarda o MEMO como nota quando ele agrega informacao alem do nome ja usado.
    def row_notes(trn)
      return "" if trn.memo.blank?
      return "" if trn.memo == trn.name

      trn.memo
    end

    # ------------------------------------------------------------------
    # Execucao da importacao
    # ------------------------------------------------------------------

    def import_transaction_rows!
      rows.each do |row|
        entry = account.entries.build \
          date:     row.date_iso,
          amount:   row.signed_amount,
          name:     row.name,
          currency: row.currency,
          notes:    row.notes,
          entryable: Transaction.new,
          import:   self

        entry.save!
      end
    end

    # ------------------------------------------------------------------
    # Saldo / ancora de saldo inicial
    # ------------------------------------------------------------------

    # O LEDGERBAL do OFX e o saldo ATUAL (ao fim do extrato), nao o inicial.
    # Derivamos a ancora de abertura subtraindo do saldo final a soma de todas
    # as transacoes importadas, e a datamos um dia antes da transacao mais antiga.
    def apply_ledger_balance_anchor!
      balance = OfxParser.parse_balance(raw_file_str)
      return unless balance&.amount

      earliest = earliest_row_date
      return unless earliest.present?

      net_movement   = rows.sum { |row| row.amount.to_d }
      opening_amount = balance.amount.to_d - net_movement

      Account::OpeningBalanceManager.new(account).set_opening_balance(
        balance: opening_amount,
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
end
