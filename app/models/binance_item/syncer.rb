# Orquestra o sync de uma conexao Binance e -- ponto central do escopo -- traduz
# rejeicoes por geografia/regulacao/permissao em mensagem ACIONAVEL em pt-BR,
# sem deixar o item num estado quebrado (fica em `requires_update`, recuperavel).
class BinanceItem::Syncer
  attr_reader :binance_item

  def initialize(binance_item)
    @binance_item = binance_item
  end

  def perform_sync(sync)
    unless binance_item.credentials_configured?
      fail_with(:credentials_missing)
      return
    end

    # Importa da Binance (pode levantar os erros tipados de Provider::Binance)
    binance_item.import_latest_binance_data

    # Sucesso: limpa qualquer estado de erro anterior
    binance_item.update!(status: :good, last_error: nil) if binance_item.requires_update?

    # Cria/atualiza as Accounts do dominio e converte saldos para a moeda da familia
    binance_item.process_accounts

    # Agenda syncs de conta para saldos historicos
    binance_item.schedule_account_syncs(
      parent_sync: sync,
      window_start_date: sync.window_start_date,
      window_end_date: sync.window_end_date
    )
  rescue Provider::Binance::GeoRestrictedError => e
    fail_with(:geo_restricted, e)
  rescue Provider::Binance::PermissionError => e
    fail_with(:permission, e)
  rescue Provider::Binance::AuthenticationError => e
    fail_with(:authentication, e)
  rescue Provider::Binance::RateLimitError => e
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
      message = I18n.t("binance_item.syncer.errors.#{reason}")
      Rails.logger.warn("BinanceItem::Syncer ##{binance_item.id} - #{reason}: #{error&.message}")
      # update_columns: grava o estado de erro sem reentrar nas validacoes de
      # presenca das credenciais (que barrariam o caso credentials_missing).
      binance_item.update_columns(status: "requires_update", last_error: message)
      raise Provider::Binance::Error, message
    end
end
