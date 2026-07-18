# Conexao de uma familia com o Mercado Bitcoin via API-KEY (TAPI id/secret) do
# proprio usuario (colar, sem OAuth). E "so mais um provider" da fundacao
# generica: cada MercadoBitcoinAccount vinculado alcanca sua Account pelo
# AccountProvider.
#
# Modelado 1:1 sobre o BinanceItem do Muquirana (Syncable + Provided + sync
# system). A diferenca de negocio: o Mercado Bitcoin ja opera em BRL nativamente,
# entao nao ha conversao USD->BRL (o processor e mais simples).
class MercadoBitcoinItem < ApplicationRecord
  include Syncable, Provided

  enum :status, { good: "good", requires_update: "requires_update" }, default: :good

  # Credenciais da API, cifradas incondicionalmente -- mesmo criterio de
  # PlaidItem#access_token. api_key deterministico para permitir consulta.
  encrypts :api_key, deterministic: true
  encrypts :api_secret

  validates :name, :api_key, :api_secret, presence: true

  belongs_to :family

  has_many :mercado_bitcoin_accounts, dependent: :destroy
  has_many :accounts, through: :mercado_bitcoin_accounts, source: :account

  after_create :set_mercado_bitcoin_institution_defaults

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

  # Busca os dados no Mercado Bitcoin e materializa/atualiza os MercadoBitcoinAccounts.
  def import_latest_mercado_bitcoin_data
    MercadoBitcoinItem::Importer.new(self, mercado_bitcoin_provider: mercado_bitcoin_provider).import
  end

  # Processa cada MercadoBitcoinAccount: cria/atualiza a Account do dominio (via
  # AccountProvider). Saldo ja vem em BRL nativo -- sem conversao.
  def process_accounts
    mercado_bitcoin_accounts.each do |mb_account|
      MercadoBitcoinAccount::Processor.new(mb_account).process
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

  def upsert_mercado_bitcoin_snapshot!(payload)
    update!(raw_payload: payload)
  end

  def institution_display_name
    institution_name.presence || name
  end

  private
    def set_mercado_bitcoin_institution_defaults
      # update_columns: so metadados nao cifrados; evita reentrar em callbacks.
      update_columns(
        institution_name: "Mercado Bitcoin",
        institution_domain: "mercadobitcoin.com.br",
        institution_url: "https://www.mercadobitcoin.com.br",
        institution_color: "#F5A623"
      )
    end
end
