# Orquestra o sync de uma conexao Mercado Bitcoin e -- ponto central do escopo --
# traduz rejeicoes por chave invalida/permissao em mensagem ACIONAVEL em pt-BR,
# sem deixar o item num estado quebrado (fica em `requires_update`, recuperavel).
class MercadoBitcoinItem::Syncer
  attr_reader :mercado_bitcoin_item

  def initialize(mercado_bitcoin_item)
    @mercado_bitcoin_item = mercado_bitcoin_item
  end

  def perform_sync(sync)
    unless mercado_bitcoin_item.credentials_configured?
      fail_with(:credentials_missing)
      return
    end

    # Importa do Mercado Bitcoin (pode levantar os erros tipados de Provider::MercadoBitcoin)
    mercado_bitcoin_item.import_latest_mercado_bitcoin_data

    # Sucesso: limpa qualquer estado de erro anterior
    if mercado_bitcoin_item.requires_update?
      mercado_bitcoin_item.update!(status: :good, last_error: nil)
    end

    # Cria/atualiza as Accounts do dominio (saldo ja em BRL nativo)
    mercado_bitcoin_item.process_accounts

    # Agenda syncs de conta para saldos historicos
    mercado_bitcoin_item.schedule_account_syncs(
      parent_sync: sync,
      window_start_date: sync.window_start_date,
      window_end_date: sync.window_end_date
    )
  rescue Provider::MercadoBitcoin::PermissionError => e
    fail_with(:permission, e)
  rescue Provider::MercadoBitcoin::AuthenticationError => e
    fail_with(:authentication, e)
  rescue Provider::MercadoBitcoin::RateLimitError => e
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
      message = I18n.t("mercado_bitcoin_item.syncer.errors.#{reason}")
      Rails.logger.warn("MercadoBitcoinItem::Syncer ##{mercado_bitcoin_item.id} - #{reason}: #{error&.message}")
      # update_columns: grava o estado de erro sem reentrar nas validacoes de
      # presenca das credenciais (que barrariam o caso credentials_missing).
      mercado_bitcoin_item.update_columns(status: "requires_update", last_error: message)
      raise Provider::MercadoBitcoin::Error, message
    end
end
