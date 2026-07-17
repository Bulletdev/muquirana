class IdentifyRecurringTransactionsJob < ApplicationJob
  queue_as :default

  # Debounce: chamado varias vezes dentro da janela, so o ultimo job agendado
  # roda de fato.
  DEBOUNCE_DELAY = 30.seconds

  def perform(family_id, scheduled_at)
    family = Family.find_by(id: family_id)
    return unless family

    # Job velho (um mais novo foi agendado depois): descarta.
    latest_scheduled = Rails.cache.read(cache_key(family_id))
    return if latest_scheduled && latest_scheduled > scheduled_at

    # Ainda ha syncs em andamento: pula e deixa o ultimo sync disparar de novo.
    return if family_has_incomplete_syncs?(family)

    # Advisory lock como rede de seguranca final contra execucao concorrente.
    with_advisory_lock(family_id) do
      RecurringTransaction::Identifier.new(family).identify_recurring_patterns
    end
  end

  def self.schedule_for(family)
    scheduled_at = Time.current.to_f
    cache_key = "recurring_transaction_identify:#{family.id}"

    Rails.cache.write(cache_key, scheduled_at, expires_in: DEBOUNCE_DELAY + 10.seconds)

    set(wait: DEBOUNCE_DELAY).perform_later(family.id, scheduled_at)
  end

  private
    def cache_key(family_id)
      "recurring_transaction_identify:#{family_id}"
    end

    # Gate de debounce: enquanto o sync-pai da familia (ou seus filhos) nao
    # finaliza, ele fica "incomplete" e adiamos a identificacao para nao rodar
    # sobre um dataset parcial.
    def family_has_incomplete_syncs?(family)
      family.syncs.incomplete.exists?
    end

    def with_advisory_lock(family_id)
      lock_key = advisory_lock_key(family_id)
      acquired = ActiveRecord::Base.connection.select_value(
        ActiveRecord::Base.sanitize_sql_array([ "SELECT pg_try_advisory_lock(?)", lock_key ])
      )

      return unless acquired

      begin
        yield
      ensure
        ActiveRecord::Base.connection.execute(
          ActiveRecord::Base.sanitize_sql_array([ "SELECT pg_advisory_unlock(?)", lock_key ])
        )
      end
    end

    def advisory_lock_key(family_id)
      # Chave inteira estavel a partir do family_id para o advisory lock (bigint).
      Digest::MD5.hexdigest("recurring_transaction_identify:#{family_id}").to_i(16) % (2**31)
    end
end
