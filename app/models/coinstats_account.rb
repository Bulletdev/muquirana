# Uma carteira on-chain rastreada via CoinStats (endereco publico + chain). E uma
# conta AGREGADA: seu saldo (em USD) e a soma do valor de todos os tokens
# on-chain + posicoes DeFi daquele endereco naquela chain.
class CoinstatsAccount < ApplicationRecord
  belongs_to :coinstats_item

  # Fundacao generica de providers: a Account alcanca seu CoinstatsAccount pelo
  # join polimorfico AccountProvider (sem FK direta, sem hardcode).
  has_one :account_provider, as: :provider, dependent: :destroy
  has_one :account, through: :account_provider, source: :account

  validates :name, :currency, presence: true
  # account_id codifica a chain -> unico por (item, endereco, chain).
  validates :account_id, uniqueness: { scope: %i[coinstats_item_id wallet_address], allow_nil: true }

  # Garante o vinculo AccountProvider entre este CoinstatsAccount e uma Account.
  def ensure_account_provider!(linked_account)
    return nil unless linked_account

    AccountProvider
      .find_or_initialize_by(provider_type: "CoinstatsAccount", provider_id: id)
      .tap do |ap|
        ap.account = linked_account
        ap.save!
      end
  end
end
