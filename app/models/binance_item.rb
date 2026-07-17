# Conexao de uma familia com a Binance via API-KEY do proprio usuario (colar
# api_key/api_secret, sem OAuth). E "so mais um provider" da fundacao generica:
# cada BinanceAccount vinculado alcanca sua Account pelo AccountProvider.
#
# Modelado sobre o PlaidItem do Muquirana (Syncable + Provided + sync system),
# NAO sobre o BinanceItem do Sure (que depende de HTTParty/Encryptable/SyncStats
# ausentes aqui). A logica de negocio (spot, saldo, erros) veio do Sure.
class BinanceItem < ApplicationRecord
  include Syncable, Provided

  enum :status, { good: "good", requires_update: "requires_update" }, default: :good

  # Credenciais da API, cifradas incondicionalmente -- mesmo criterio de
  # PlaidItem#access_token. api_key deterministico para permitir consulta.
  encrypts :api_key, deterministic: true
  encrypts :api_secret

  validates :name, :api_key, :api_secret, presence: true

  belongs_to :family

  has_many :binance_accounts, dependent: :destroy
  has_many :accounts, through: :binance_accounts, source: :account

  after_create :set_binance_institution_defaults

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

  # Busca os dados na Binance e materializa/atualiza os BinanceAccounts.
  def import_latest_binance_data
    BinanceItem::Importer.new(self, binance_provider: binance_provider).import
  end

  # Processa cada BinanceAccount: cria/atualiza a Account do dominio (via
  # AccountProvider) e converte o saldo para a moeda da familia.
  def process_accounts
    binance_accounts.each do |binance_account|
      BinanceAccount::Processor.new(binance_account).process
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

  def upsert_binance_snapshot!(payload)
    update!(raw_payload: payload)
  end

  def institution_display_name
    institution_name.presence || name
  end

  private
    def set_binance_institution_defaults
      # update_columns: so metadados nao cifrados; evita reentrar em callbacks.
      update_columns(
        institution_name: "Binance",
        institution_domain: "binance.com",
        institution_url: "https://www.binance.com",
        institution_color: "#F0B90B"
      )
    end
end
