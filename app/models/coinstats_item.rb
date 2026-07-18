# Conexao de uma familia com o CoinStats via chave OpenAPI do proprio usuario
# (colar api_key, sem OAuth). Rastreia carteiras on-chain por ENDERECO PUBLICO
# (MetaMask/DeFi) -- e "so mais um provider" da fundacao generica: cada
# CoinstatsAccount vinculado alcanca sua Account pelo AccountProvider.
#
# Modelado sobre o BinanceItem/PlaidItem do Muquirana (Syncable + Provided + sync
# system). A logica de negocio (carteira on-chain, DeFi, conversao) veio do
# CoinstatsItem do Sure, fatiada para o MVP: apenas carteira por endereco + DeFi
# (o fluxo de "exchange via CoinStats" ficou de fora, redundante com Binance/MB).
class CoinstatsItem < ApplicationRecord
  include Syncable, Provided

  enum :status, { good: "good", requires_update: "requires_update" }, default: :good

  # Chave OpenAPI, cifrada incondicionalmente -- mesmo criterio de
  # BinanceItem#api_key. Deterministico para permitir consulta.
  encrypts :api_key, deterministic: true

  validates :name, :api_key, presence: true

  belongs_to :family

  has_many :coinstats_accounts, dependent: :destroy
  has_many :accounts, through: :coinstats_accounts, source: :account

  after_create :set_coinstats_institution_defaults

  scope :active, -> { where(scheduled_for_deletion: false) }
  # Contrato consumido pelo Family::Syncer reflexivo: sincronizavel = ativo.
  scope :syncable, -> { active }
  scope :ordered, -> { order(created_at: :desc) }
  scope :needs_update, -> { where(status: :requires_update) }

  def credentials_configured?
    api_key.present?
  end

  def destroy_later
    update!(scheduled_for_deletion: true)
    DestroyJob.perform_later(self)
  end

  # Vincula uma carteira on-chain (endereco + chain), busca saldos + DeFi e
  # materializa uma unica Account agregada por carteira. Ver WalletLinker.
  def link_wallet!(address:, blockchain:)
    CoinstatsItem::WalletLinker.new(self, address: address, blockchain: blockchain).link
  end

  # Vincula o MESMO endereco em varias blockchains de uma vez (cola uma vez, marca
  # as chains). Busca os saldos em lote e cria conta so onde ha saldo. Ver
  # WalletBatchLinker.
  def link_wallets!(address:, blockchains:, import_empty: false)
    CoinstatsItem::WalletBatchLinker.new(self, address: address, blockchains: blockchains, import_empty: import_empty).link
  end

  # Rebusca saldos + DeFi de cada carteira ja vinculada e atualiza os
  # CoinstatsAccounts. Chamado a cada sync.
  def import_latest_coinstats_data
    CoinstatsItem::Importer.new(self, coinstats_provider: coinstats_provider).import
  end

  # Materializa/atualiza a Account do dominio para cada CoinstatsAccount e
  # converte o saldo (USD) para a moeda da familia (BRL).
  def process_accounts
    coinstats_accounts.each do |coinstats_account|
      CoinstatsAccount::Processor.new(coinstats_account).process
    end
  end

  def schedule_account_syncs(parent_sync: nil, window_start_date: nil, window_end_date: nil)
    accounts.each do |account|
      account.sync_later(
        parent_sync: parent_sync,
        window_start_date: window_start_date,
        window_end_date: window_end_date
      )
    end
  end

  def upsert_coinstats_snapshot!(payload)
    update!(raw_payload: payload)
  end

  def institution_display_name
    institution_name.presence || name
  end

  private
    def set_coinstats_institution_defaults
      update_columns(
        institution_name: "CoinStats",
        institution_domain: "coinstats.app",
        institution_url: "https://coinstats.app",
        institution_color: "#7C3AED"
      )
    end
end
