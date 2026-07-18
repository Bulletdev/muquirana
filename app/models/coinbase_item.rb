# Conexao de uma familia com a Coinbase via chave CDP (Coinbase Developer
# Platform) do proprio usuario (colar nome da chave + chave privada EC, sem
# OAuth). E "so mais um provider" da fundacao generica: cada CoinbaseAccount
# vinculado alcanca sua Account pelo AccountProvider.
#
# Modelado sobre o BinanceItem do Muquirana (Syncable + Provided + sync system),
# NAO sobre o CoinbaseItem do Sure (que depende de Encryptable/SyncStats/Unlinking
# ausentes ou diferentes aqui). A logica de negocio (carteiras, holdings, erros)
# veio do Sure, adaptada para holdings em BRL via Security::Resolver.
class CoinbaseItem < ApplicationRecord
  include Syncable, Provided

  enum :status, { good: "good", requires_update: "requires_update" }, default: :good

  # Credenciais CDP, cifradas incondicionalmente -- mesmo criterio de
  # PlaidItem#access_token. api_key deterministico para permitir consulta.
  encrypts :api_key, deterministic: true
  encrypts :api_secret

  validates :name, :api_key, :api_secret, presence: true

  belongs_to :family

  has_many :coinbase_accounts, dependent: :destroy
  has_many :accounts, through: :coinbase_accounts, source: :account

  after_create :set_coinbase_institution_defaults

  scope :active, -> { where(scheduled_for_deletion: false) }
  # Contrato consumido pelo Family::Syncer reflexivo: sincronizavel = ativo.
  scope :syncable, -> { active }
  scope :ordered, -> { order(created_at: :desc) }
  scope :needs_update, -> { where(status: :requires_update) }

  def credentials_configured?
    api_key.present? && api_secret.present?
  end

  def destroy_later
    update!(scheduled_for_deletion: true)
    DestroyJob.perform_later(self)
  end

  # Busca as carteiras na Coinbase e materializa/atualiza os CoinbaseAccounts.
  def import_latest_coinbase_data
    CoinbaseItem::Importer.new(self, coinbase_provider: coinbase_provider).import
  end

  # Processa cada CoinbaseAccount: cria/atualiza a Account do dominio (via
  # AccountProvider), cria os Holdings (um por cripto) em BRL e ajusta o saldo.
  def process_accounts
    coinbase_accounts.each do |coinbase_account|
      CoinbaseAccount::Processor.new(coinbase_account).process
    end
  end

  # Depois de tudo importado, agenda syncs de conta para calcular saldos historicos.
  def schedule_account_syncs(parent_sync: nil, window_start_date: nil, window_end_date: nil)
    accounts.each do |account|
      account.sync_later(
        parent_sync: parent_sync,
        window_start_date: window_start_date,
        window_end_date: window_end_date
      )
    end
  end

  def upsert_coinbase_snapshot!(payload)
    update!(raw_payload: payload)
  end

  def institution_display_name
    institution_name.presence || name
  end

  private
    def set_coinbase_institution_defaults
      # update_columns: so metadados nao cifrados; evita reentrar em callbacks.
      update_columns(
        institution_name: "Coinbase",
        institution_domain: "coinbase.com",
        institution_url: "https://www.coinbase.com",
        institution_color: "#0052FF"
      )
    end
end
