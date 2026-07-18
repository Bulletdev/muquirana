# Orquestra o sync de uma conexao Coinbase e -- ponto central do escopo -- traduz
# rejeicoes por chave invalida/permissao em mensagem ACIONAVEL em pt-BR, sem
# deixar o item num estado quebrado (fica em `requires_update`, recuperavel).
class CoinbaseItem::Syncer
  attr_reader :coinbase_item

  def initialize(coinbase_item)
    @coinbase_item = coinbase_item
  end

  def perform_sync(sync)
    unless coinbase_item.credentials_configured?
      fail_with(:credentials_missing)
      return
    end

    # Importa da Coinbase (pode levantar os erros tipados de Provider::Coinbase)
    coinbase_item.import_latest_coinbase_data

    # Sucesso: limpa qualquer estado de erro anterior
    coinbase_item.update!(status: :good, last_error: nil) if coinbase_item.requires_update?

    # Cria/atualiza as Accounts do dominio, os Holdings (BRL) e o saldo
    coinbase_item.process_accounts

    # Agenda syncs de conta para saldos historicos
    coinbase_item.schedule_account_syncs(
      parent_sync: sync,
      window_start_date: sync.window_start_date,
      window_end_date: sync.window_end_date
    )
  rescue Provider::Coinbase::PermissionError => e
    fail_with(:permission, e)
  rescue Provider::Coinbase::AuthenticationError => e
    fail_with(:authentication, e)
  rescue Provider::Coinbase::RateLimitError => e
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
      message = I18n.t("coinbase_item.syncer.errors.#{reason}")
      Rails.logger.warn("CoinbaseItem::Syncer ##{coinbase_item.id} - #{reason}: #{error&.message}")
      # update_columns: grava o estado de erro sem reentrar nas validacoes de
      # presenca das credenciais (que barrariam o caso credentials_missing).
      coinbase_item.update_columns(status: "requires_update", last_error: message)
      raise Provider::Coinbase::Error, message
    end
end
