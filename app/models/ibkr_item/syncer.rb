# Orquestra o sync de uma conexao IBKR e -- ponto central do escopo -- traduz as
# rejeicoes (query_id/token invalido, query mal configurada, extrato ainda nao
# pronto) em mensagem ACIONAVEL em pt-BR, sem deixar o item num estado quebrado
# (fica em `requires_update`, recuperavel).
class IbkrItem::Syncer
  attr_reader :ibkr_item

  def initialize(ibkr_item)
    @ibkr_item = ibkr_item
  end

  def perform_sync(sync)
    unless ibkr_item.credentials_configured?
      fail_with(:credentials_missing)
      return
    end

    # Importa o extrato Flex (pode levantar os erros tipados de Provider::IbkrFlex)
    ibkr_item.import_latest_ibkr_data

    # Sucesso: limpa qualquer estado de erro anterior
    ibkr_item.update!(status: :good, last_error: nil) if ibkr_item.requires_update?

    # Materializa Accounts/Holdings/Trades e converte multi-moeda -> moeda da familia
    ibkr_item.process_accounts

    # Agenda syncs de conta para saldos historicos
    ibkr_item.schedule_account_syncs(
      parent_sync: sync,
      window_start_date: sync.window_start_date,
      window_end_date: sync.window_end_date
    )
  rescue Provider::IbkrFlex::StatementNotReadyError => e
    fail_with(:statement_not_ready, e)
  rescue Provider::IbkrFlex::InvalidQueryError => e
    fail_with(:invalid_query, e)
  rescue Provider::IbkrFlex::AuthenticationError => e
    fail_with(:authentication, e)
  rescue Provider::IbkrFlex::RateLimitError => e
    fail_with(:rate_limited, e)
  end

  def perform_post_sync
    # no-op
  end

  private
    # Marca o item como precisando de atencao (recuperavel) e propaga uma mensagem
    # acionavel em pt-BR. Sync#perform captura o raise, grava em sync.error e
    # marca o sync como failed -- entao a mensagem chega ao usuario via sync_error.
    def fail_with(reason, error = nil)
      message = I18n.t("ibkr_item.syncer.errors.#{reason}")
      Rails.logger.warn("IbkrItem::Syncer ##{ibkr_item.id} - #{reason}: #{error&.message}")
      # update_columns: grava o estado de erro sem reentrar nas validacoes de
      # presenca das credenciais (que barrariam o caso credentials_missing).
      ibkr_item.update_columns(status: "requires_update", last_error: message)
      raise Provider::IbkrFlex::Error, message
    end
end
