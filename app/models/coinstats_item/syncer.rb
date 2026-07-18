# Orquestra o sync de uma conexao CoinStats e -- ponto central do escopo BR --
# traduz os dois erros mais comuns do plano gratuito (creditos esgotados/406 e
# rate-limit/429) em mensagem ACIONAVEL em pt-BR, sem deixar o item quebrado
# (fica em `requires_update`, recuperavel).
class CoinstatsItem::Syncer
  attr_reader :coinstats_item

  def initialize(coinstats_item)
    @coinstats_item = coinstats_item
  end

  def perform_sync(sync)
    return fail_with(:credentials_missing) unless coinstats_item.credentials_configured?

    # fail_with e chamado FORA do begin/rescue de proposito: ele levanta um
    # Provider::Coinstats::Error, que seria recapturado pelo `rescue ...::Error`
    # abaixo (traduzindo o erro ja traduzido). Coletamos a falha e disparamos depois.
    failure = nil

    begin
      # Rebusca saldos + DeFi de cada carteira (pode levantar os erros tipados de
      # Provider::Coinstats).
      coinstats_item.import_latest_coinstats_data

      # Sucesso: limpa qualquer estado de erro anterior.
      coinstats_item.update!(status: :good, last_error: nil) if coinstats_item.requires_update?

      # Cria/atualiza as Accounts do dominio e converte saldos para a moeda da familia.
      coinstats_item.process_accounts

      # Agenda syncs de conta para saldos historicos.
      coinstats_item.schedule_account_syncs(
        parent_sync: sync,
        window_start_date: sync.window_start_date,
        window_end_date: sync.window_end_date
      )
    rescue Provider::Coinstats::CreditsExhaustedError => e
      failure = [ :credits_exhausted, e ]
    rescue Provider::Coinstats::RateLimitError => e
      failure = [ :rate_limited, e ]
    rescue Provider::Coinstats::AuthenticationError => e
      failure = [ :authentication, e ]
    rescue Provider::Coinstats::Error => e
      failure = [ :api_error, e ]
    end

    fail_with(*failure) if failure
  end

  def perform_post_sync
    # no-op
  end

  private
    def fail_with(reason, error = nil)
      message = I18n.t("coinstats_item.syncer.errors.#{reason}")
      Rails.logger.warn("CoinstatsItem::Syncer ##{coinstats_item.id} - #{reason}: #{error&.message}")
      # update_columns: grava o estado de erro sem reentrar nas validacoes de
      # presenca das credenciais (que barrariam o caso credentials_missing).
      coinstats_item.update_columns(status: "requires_update", last_error: message)
      raise Provider::Coinstats::Error, message
    end
end
