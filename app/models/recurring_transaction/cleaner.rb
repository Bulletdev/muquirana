class RecurringTransaction
  class Cleaner
    attr_reader :family

    def initialize(family)
      @family = family
    end

    # Marca recorrencias como inativas quando nao ocorrem ha muito tempo.
    # 2 meses para automaticas, 6 meses para manuais.
    def cleanup_stale_transactions
      stale_count = 0

      family.recurring_transactions
            .active
            .find_each do |recurring_transaction|
        next unless recurring_transaction.should_be_inactive?

        threshold = recurring_transaction.manual? ? 6.months.ago.to_date : 2.months.ago.to_date
        recent_matches = recurring_transaction.matching_transactions.select { |entry| entry.date >= threshold }

        if recent_matches.empty?
          recurring_transaction.mark_inactive!
          stale_count += 1
        end
      end

      stale_count
    end

    # Remove recorrencias automaticas inativas ha 6+ meses.
    # Recorrencias manuais nunca sao apagadas automaticamente.
    def remove_old_inactive_transactions
      family.recurring_transactions
        .inactive
        .where(manual: false)
        .where("updated_at < ?", 6.months.ago)
        .destroy_all
    end
  end
end
