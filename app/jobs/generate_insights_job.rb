class GenerateInsightsJob < ApplicationJob
  queue_as :scheduled

  # Sem args (cron): faz fan-out de um job por familia.
  # Com family_id: gera e faz upsert dos insights daquela familia.
  def perform(family_id: nil)
    if family_id.present?
      generate_for_family(family_id)
    else
      fan_out
    end
  end

  private
    def fan_out
      Family.find_each do |family|
        GenerateInsightsJob.perform_later(family_id: family.id)
      rescue => e
        Rails.logger.error("Failed to enqueue insight generation for family #{family.id}: #{e.message}")
      end
    end

    def generate_for_family(family_id)
      family = Family.find_by(id: family_id)
      return unless family
      return if family.accounts.none?

      with_advisory_lock(family_id) do
        I18n.with_locale(family.locale) do
          result = Insight::GeneratorRegistry.new(family).generate_all
          upsert_insights(family, result.insights)
          expire_stale_insights(family, result)
        end
      end

      # Fora do lock de proposito: mesmo uma execucao pulada pelo lock
      # re-transmite o estado atual, entao uma pagina /insights inscrita
      # (esperando seu refresh manual) sempre recebe sua lista e botao de volta.
      broadcast_feed(family)
    end

    def broadcast_feed(family)
      insights = family.insights.visible.ordered.to_a
      unread_ids = insights.select(&:active?).map(&:id).to_set

      Turbo::StreamsChannel.broadcast_replace_to(
        [ family, :insights ],
        target: "insights-list",
        partial: "insights/list",
        locals: { insights: insights, unread_ids: unread_ids }
      )
      Turbo::StreamsChannel.broadcast_replace_to(
        [ family, :insights ],
        target: "insights-refresh",
        partial: "insights/refresh_button",
        locals: { pending: false }
      )
    end

    # Um insight visivel cujo gerador rodou com sucesso mas nao re-emitiu seu
    # dedup_key teve sua condicao encerrada -- esconde-o. Tipos cujo gerador
    # quebrou ficam intocados para que uma falha transitoria nao apague insights
    # saudaveis.
    def expire_stale_insights(family, result)
      family.insights
        .visible
        .where(insight_type: result.succeeded_types)
        .where.not(dedup_key: result.insights.map(&:dedup_key))
        .update_all(status: "expired", updated_at: Time.current)
    end

    def upsert_insights(family, generated_insights)
      writer = Insight::BodyWriter.new(family)

      generated_insights.each do |generated|
        metadata = normalize_json(generated.metadata)
        facts = normalize_json(generated.facts)
        existing = family.insights.find_by(dedup_key: generated.dedup_key)

        if existing.nil?
          family.insights.create!(
            insight_type: generated.insight_type,
            priority: generated.priority,
            status: "active",
            title: generated.title,
            body: writer.write(generated),
            metadata: metadata,
            facts: facts,
            currency: generated.currency,
            period_start: generated.period_start,
            period_end: generated.period_end,
            generated_at: Time.current,
            dedup_key: generated.dedup_key
          )
        elsif existing.metadata != metadata
          # Os numeros mudaram materialmente: atualiza a prosa e ressurge o
          # insight mesmo que o usuario tivesse lido ou dispensado a versao velha.
          existing.update!(
            priority: generated.priority,
            status: "active",
            title: generated.title,
            body: writer.write(generated),
            metadata: metadata,
            facts: facts,
            period_start: generated.period_start,
            period_end: generated.period_end,
            generated_at: Time.current,
            read_at: nil,
            dismissed_at: nil
          )
        elsif existing.expired?
          # A condicao encerrou antes e agora voltou com os mesmos numeros. A
          # expiracao foi obra do sistema, nao do usuario, entao o insight
          # ressurge; o body ainda esta correto, entao sem reescrita.
          existing.update!(status: "active", facts: facts, generated_at: Time.current, read_at: nil)
        else
          # Mesmo sinal, mesmos numeros: nao reescreve o body (evita uma chamada
          # LLM) e nao desfaz o estado lido/dispensado do usuario. Os facts ainda
          # atualizam -- sao valores de exibicao (figura-chave, rotulos de link),
          # e mante-los atuais e exatamente por que nao fazem parte da comparacao
          # de mudanca material.
          existing.update!(facts: facts, generated_at: Time.current)
        end
      rescue ActiveRecord::RecordNotUnique
        # Uma execucao concorrente criou o mesmo dedup_key primeiro; ela e a dona
        # desta linha.
        next
      rescue => e
        Rails.logger.error(
          "GenerateInsightsJob: failed to upsert insight #{generated.dedup_key} " \
          "for family #{family.id}: #{e.class}: #{e.message}"
        )
      end
    end

    # metadata/facts do GeneratedInsight podem conter simbolos, datas ou
    # BigDecimals; as colunas jsonb persistidas convertem tudo para primitivos
    # JSON. Compare igual com igual ou toda execucao noturna pareceria uma
    # mudanca material.
    def normalize_json(hash)
      JSON.parse(hash.to_json)
    end

    def with_advisory_lock(family_id)
      lock_key = advisory_lock_key(family_id)
      acquired = ActiveRecord::Base.connection.select_value(
        ActiveRecord::Base.sanitize_sql_array([ "SELECT pg_try_advisory_lock(?)", lock_key ])
      )

      unless acquired
        Rails.logger.warn("Skipped insight generation for family #{family_id}: advisory lock unavailable")
        return
      end

      begin
        yield
      ensure
        ActiveRecord::Base.connection.execute(
          ActiveRecord::Base.sanitize_sql_array([ "SELECT pg_advisory_unlock(?)", lock_key ])
        )
      end
    end

    def advisory_lock_key(family_id)
      # Usa (quase) todo o espaco de bigint com sinal que pg_try_advisory_lock
      # aceita para manter as chances de colisao entre familias negligiveis.
      Digest::MD5.hexdigest("generate_insights:#{family_id}").to_i(16) % (2**62)
    end
end
