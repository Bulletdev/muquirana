class CoinbaseAccount < ApplicationRecord
  belongs_to :coinbase_item

  # Fundacao generica de providers: a Account alcanca seu CoinbaseAccount pelo
  # join polimorfico AccountProvider (sem FK direta, sem hardcode).
  has_one :account_provider, as: :provider, dependent: :destroy
  has_one :account, through: :account_provider, source: :account

  validates :name, :currency, presence: true

  # Lista de ativos de cripto importados (symbol, quantity, native_amount, ...).
  def assets
    Array(raw_payload.is_a?(Hash) ? raw_payload["assets"] : nil)
  end

  # Moeda fiduciaria nativa da conta Coinbase (USD/EUR/...), base da conversao BRL.
  def native_currency
    (raw_payload.is_a?(Hash) ? raw_payload["native_currency"] : nil).presence || currency.presence || "USD"
  end

  # Garante o vinculo AccountProvider entre este CoinbaseAccount e uma Account.
  def ensure_account_provider!(linked_account)
    return nil unless linked_account

    AccountProvider
      .find_or_initialize_by(provider_type: "CoinbaseAccount", provider_id: id)
      .tap do |ap|
        ap.account = linked_account
        ap.save!
      end
  end
end
