class RecurringTransaction
  # Detecta padroes recorrentes (assinatura, salario, aluguel, boleto) a partir
  # do historico. 100% LOCAL - nao usa LLM.
  class Identifier
    attr_reader :family

    def initialize(family)
      @family = family
    end

    def identify_recurring_patterns
      three_months_ago = 3.months.ago.to_date

      # Ignora transacoes de transferencia (uma metade de um par Transfer): agrupa-las
      # sob uma unica conta produziria "padroes" incoerentes. Filtra no SQL para
      # nao carregar e descartar essas entries numa familia movimentada.
      entries_with_transactions = family.entries
        .joins("INNER JOIN transactions ON transactions.id = entries.entryable_id")
        .where(entryable_type: "Transaction")
        .where("entries.date >= ?", three_months_ago)
        .where.not("transactions.kind": Transaction::TRANSFER_KINDS)
        .includes(:entryable)
        .to_a

      # Agrupa por merchant (se houver) ou nome, junto com valor (preserva sinal),
      # moeda e conta.
      grouped_transactions = entries_with_transactions
        .select { |entry| entry.entryable.is_a?(Transaction) }
        .group_by do |entry|
          transaction = entry.entryable
          identifier = transaction.merchant_id.present? ? [ :merchant, transaction.merchant_id ] : [ :name, entry.name ]
          [ identifier, entry.amount.round(2), entry.currency, entry.account_id ]
        end

      recurring_patterns = []

      grouped_transactions.each do |(identifier, amount, currency, account_id), entries|
        next if entries.size < 3 # precisa de pelo menos 3 ocorrencias

        # A ultima ocorrencia precisa ter acontecido nos ultimos 45 dias.
        last_occurrence = entries.max_by(&:date)
        next if last_occurrence.date < 45.days.ago.to_date

        days_of_month = entries.map { |e| e.date.day }.sort

        next unless days_cluster_together?(days_of_month)

        expected_day = calculate_expected_day(days_of_month)
        identifier_type, identifier_value = identifier

        pattern = {
          amount: amount,
          currency: currency,
          account_id: account_id,
          expected_day_of_month: expected_day,
          last_occurrence_date: last_occurrence.date,
          occurrence_count: entries.size,
          entries: entries
        }

        if identifier_type == :merchant
          pattern[:merchant_id] = identifier_value
        else
          pattern[:name] = identifier_value
        end

        recurring_patterns << pattern
      end

      # Cria ou atualiza as RecurringTransaction. Carrega as linhas existentes uma
      # unica vez para nao emitir um lookup por padrao detectado.
      existing_recurring_transactions_by_key = family.recurring_transactions
        .to_a
        .index_by { |recurring| recurring_transaction_lookup_key(recurring) }

      recurring_patterns.each do |pattern|
        find_conditions = {
          amount: pattern[:amount],
          currency: pattern[:currency],
          account_id: pattern[:account_id]
        }

        if pattern[:merchant_id].present?
          find_conditions[:merchant_id] = pattern[:merchant_id]
          find_conditions[:name] = nil
        else
          find_conditions[:name] = pattern[:name]
          find_conditions[:merchant_id] = nil
        end

        begin
          lookup_key = recurring_transaction_lookup_key(find_conditions)
          recurring_transaction = existing_recurring_transactions_by_key[lookup_key] ||
                                  family.recurring_transactions.build(find_conditions)

          # Recorrencias manuais tem variancia recalculada em outra passada.
          next if recurring_transaction.persisted? && recurring_transaction.manual?

          if recurring_transaction.new_record?
            if pattern[:merchant_id].present?
              recurring_transaction.merchant_id = pattern[:merchant_id]
            else
              recurring_transaction.name = pattern[:name]
            end
            recurring_transaction.manual = false
          end

          recurring_transaction.assign_attributes(
            expected_day_of_month: pattern[:expected_day_of_month],
            last_occurrence_date: pattern[:last_occurrence_date],
            next_expected_date: calculate_next_expected_date(pattern[:last_occurrence_date], pattern[:expected_day_of_month]),
            occurrence_count: pattern[:occurrence_count],
            status: recurring_transaction.new_record? ? "active" : recurring_transaction.status
          )

          recurring_transaction.save!
          existing_recurring_transactions_by_key[lookup_key] = recurring_transaction
        rescue ActiveRecord::RecordNotUnique
          # Corrida: outro processo criou a mesma linha entre o find e o save.
          recurring_transaction = family.recurring_transactions.find_by(find_conditions)
          next unless recurring_transaction
          next if recurring_transaction.manual?

          recurring_transaction.update!(
            expected_day_of_month: pattern[:expected_day_of_month],
            last_occurrence_date: pattern[:last_occurrence_date],
            next_expected_date: calculate_next_expected_date(pattern[:last_occurrence_date], pattern[:expected_day_of_month]),
            occurrence_count: pattern[:occurrence_count]
          )
        end
      end

      update_manual_recurring_transactions(three_months_ago)

      recurring_patterns.size
    end

    # Atualiza a variancia de valor das recorrencias manuais ativas.
    def update_manual_recurring_transactions(_since_date)
      manual_recurring_transactions = family.recurring_transactions
        .where(manual: true, status: "active")
        .includes(:account)
        .to_a

      matching_entries_by_recurring_id = matching_entries_by_manual_recurring_id(
        manual_recurring_transactions,
        lookback_months: 6
      )

      manual_recurring_transactions.each do |recurring|
        matching_entries = matching_entries_by_recurring_id.fetch(recurring.id, [])
        next if matching_entries.empty?

        matching_amounts = matching_entries.map(&:amount)
        last_entry = matching_entries.max_by(&:date)

        recurring.update!(
          expected_amount_min: matching_amounts.min,
          expected_amount_max: matching_amounts.max,
          expected_amount_avg: matching_amounts.sum / matching_amounts.size,
          occurrence_count: matching_amounts.size,
          last_occurrence_date: last_entry.date,
          next_expected_date: calculate_next_expected_date(last_entry.date, recurring.expected_day_of_month)
        )
      end
    end

    private
      def recurring_transaction_lookup_key(recurring_or_attributes)
        amount = fetch_attr(recurring_or_attributes, :amount)
        currency = fetch_attr(recurring_or_attributes, :currency)
        account_id = fetch_attr(recurring_or_attributes, :account_id)
        merchant_id = fetch_attr(recurring_or_attributes, :merchant_id)
        name = fetch_attr(recurring_or_attributes, :name)

        identifier_type = merchant_id.present? ? :merchant : :name
        identifier_value = merchant_id.presence || name

        [ amount, currency, account_id, identifier_type, identifier_value ]
      end

      def fetch_attr(recurring_or_attributes, key)
        if recurring_or_attributes.respond_to?(key)
          recurring_or_attributes.public_send(key)
        else
          recurring_or_attributes[key]
        end
      end

      def matching_entries_by_manual_recurring_id(recurring_transactions, lookback_months:)
        return {} if recurring_transactions.empty?

        lookback_date = lookback_months.months.ago.to_date
        currencies = recurring_transactions.map(&:currency).uniq
        account_ids = recurring_transactions.filter_map(&:account_id).uniq

        entries = family.entries
          .joins("INNER JOIN transactions ON transactions.id = entries.entryable_id AND entries.entryable_type = 'Transaction'")
          .where(entries: { entryable_type: "Transaction", currency: currencies })
          .where("entries.date >= ?", lookback_date)
          .select("entries.*, transactions.merchant_id AS transaction_merchant_id")
          .order(date: :desc)

        if account_ids.any? && recurring_transactions.all? { |recurring| recurring.account_id.present? }
          entries = entries.where(entries: { account_id: account_ids })
        end

        candidate_entries = entries.to_a

        recurring_transactions.to_h do |recurring|
          [
            recurring.id,
            candidate_entries.select { |entry| manual_recurring_matches_entry?(recurring, entry) }
          ]
        end
      end

      def manual_recurring_matches_entry?(recurring, entry)
        return false unless entry.currency == recurring.currency
        return false if recurring.account_id.present? && entry.account_id != recurring.account_id

        expected_day = [ recurring.expected_day_of_month, entry.date.end_of_month.day ].min
        return false if circular_distance(entry.date.day, expected_day) > 2

        if recurring.merchant_id.present?
          entry.read_attribute("transaction_merchant_id") == recurring.merchant_id
        else
          entry.name == recurring.name
        end
      end

      # Verifica se os dias se agrupam (~5 dias de desvio). Usa distancia circular
      # para lidar com a virada de mes (ex.: 28, 29, 30, 31, 1, 2).
      def days_cluster_together?(days)
        return false if days.empty?

        median = calculate_expected_day(days)
        circular_distances = days.map { |day| circular_distance(day, median) }

        mean_distance = circular_distances.sum.to_f / circular_distances.size
        variance = circular_distances.map { |dist| (dist - mean_distance)**2 }.sum / circular_distances.size
        std_dev = Math.sqrt(variance)

        std_dev <= 5
      end

      # Distancia circular entre dois dias num circulo de 31.
      def circular_distance(day1, day2)
        linear_distance = (day1 - day2).abs
        wrap_distance = 31 - linear_distance
        [ linear_distance, wrap_distance ].min
      end

      # Dia esperado a partir do dia mais comum. Usa rotacao circular para lidar
      # com sequencias que viram o mes (ex.: [29, 30, 31, 1, 2]).
      def calculate_expected_day(days)
        return days.first if days.size == 1

        days_0 = days.map { |d| d - 1 }

        best_pivot = 0
        min_span = Float::INFINITY

        (0..30).each do |pivot|
          rotated = days_0.map { |d| (d - pivot) % 31 }
          span = rotated.max - rotated.min

          if span < min_span
            min_span = span
            best_pivot = pivot
          end
        end

        rotated_days = days_0.map { |d| (d - best_pivot) % 31 }.sort

        mid = rotated_days.size / 2
        rotated_median = if rotated_days.size.odd?
          rotated_days[mid]
        else
          ((rotated_days[mid - 1] + rotated_days[mid]) / 2.0).round
        end

        (rotated_median + best_pivot) % 31 + 1
      end

      def calculate_next_expected_date(last_date, expected_day)
        next_month = last_date.next_month
        begin
          Date.new(next_month.year, next_month.month, expected_day)
        rescue ArgumentError
          next_month.end_of_month
        end
      end
  end
end
