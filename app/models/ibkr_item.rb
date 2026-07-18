# Conexao de uma familia com a Interactive Brokers via Flex Query do proprio
# usuario (colar query_id + token, sem OAuth). E "so mais um provider" da
# fundacao generica: cada IbkrAccount vinculado alcanca sua Account pelo
# AccountProvider.
#
# Modelado sobre o BinanceItem/MercadoBitcoinItem do Muquirana (Syncable +
# Provided + sync system). A diferenca de negocio: a IBKR e um provider de
# INVESTIMENTO -- materializa posicoes (Holding) e trades (Trade), multi-moeda
# convertida para a moeda da familia (BRL).
class IbkrItem < ApplicationRecord
  include Syncable, Provided

  enum :status, { good: "good", requires_update: "requires_update" }, default: :good

  # Credenciais da Flex Query, cifradas incondicionalmente -- mesmo criterio de
  # PlaidItem#access_token. query_id deterministico para permitir consulta.
  encrypts :query_id, deterministic: true
  encrypts :token

  validates :name, :query_id, :token, presence: true

  belongs_to :family

  has_many :ibkr_accounts, dependent: :destroy
  has_many :accounts, through: :ibkr_accounts, source: :account

  after_create :set_ibkr_institution_defaults

  scope :active, -> { where(scheduled_for_deletion: false) }
  # Contrato consumido pelo Family::Syncer reflexivo: sincronizavel = ativo.
  scope :syncable, -> { active }
  scope :ordered, -> { order(created_at: :desc) }
  scope :needs_update, -> { where(status: :requires_update) }

  def credentials_configured?
    query_id.present? && token.present?
  end

  def destroy_later
    update!(scheduled_for_deletion: true)
    DestroyJob.perform_later(self)
  end

  # Baixa o extrato Flex da IBKR e materializa/atualiza os IbkrAccounts.
  def import_latest_ibkr_data
    IbkrItem::Importer.new(self, ibkr_provider: ibkr_provider).import
  end

  # Processa cada IbkrAccount: cria/atualiza a Account do dominio (via
  # AccountProvider), materializa holdings/trades e converte para a moeda da familia.
  def process_accounts
    ibkr_accounts.each do |ibkr_account|
      IbkrAccount::Processor.new(ibkr_account).process
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

  def upsert_ibkr_snapshot!(payload)
    update!(raw_payload: payload)
  end

  def institution_display_name
    institution_name.presence || name
  end

  private
    def set_ibkr_institution_defaults
      # update_columns: so metadados nao cifrados; evita reentrar em callbacks.
      update_columns(
        institution_name: "Interactive Brokers",
        institution_domain: "interactivebrokers.com",
        institution_url: "https://www.interactivebrokers.com",
        institution_color: "#D32F2F"
      )
    end
end
