class MercadoBitcoinAccount < ApplicationRecord
  belongs_to :mercado_bitcoin_item

  # Fundacao generica de providers: a Account alcanca seu MercadoBitcoinAccount
  # pelo join polimorfico AccountProvider (sem FK direta, sem hardcode).
  has_one :account_provider, as: :provider, dependent: :destroy
  has_one :account, through: :account_provider, source: :account

  validates :name, :currency, presence: true

  # Garante o vinculo AccountProvider entre este MercadoBitcoinAccount e uma Account.
  def ensure_account_provider!(linked_account)
    return nil unless linked_account

    AccountProvider
      .find_or_initialize_by(provider_type: "MercadoBitcoinAccount", provider_id: id)
      .tap do |ap|
        ap.account = linked_account
        ap.save!
      end
  end
end
