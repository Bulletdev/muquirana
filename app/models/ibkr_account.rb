class IbkrAccount < ApplicationRecord
  include IbkrAccount::DataHelpers

  belongs_to :ibkr_item

  # Fundacao generica de providers: a Account alcanca seu IbkrAccount pelo join
  # polimorfico AccountProvider (sem FK direta, sem hardcode).
  has_one :account_provider, as: :provider, dependent: :destroy
  has_one :account, through: :account_provider, source: :account

  validates :name, :currency, presence: true
  validates :ibkr_account_id, uniqueness: { scope: :ibkr_item_id, allow_nil: true }

  # Garante o vinculo AccountProvider entre este IbkrAccount e uma Account.
  def ensure_account_provider!(linked_account)
    return nil unless linked_account

    AccountProvider
      .find_or_initialize_by(provider_type: "IbkrAccount", provider_id: id)
      .tap do |ap|
        ap.account = linked_account
        ap.save!
      end
  end

  # Materializa/atualiza este IbkrAccount a partir de um bloco parseado do extrato.
  def upsert_from_ibkr_statement!(account_data)
    data = account_data.with_indifferent_access

    update!(
      ibkr_account_id: data[:ibkr_account_id],
      name: data[:name].presence || data[:ibkr_account_id],
      currency: parse_currency(data[:currency]) || "USD",
      current_balance: data[:current_balance],
      cash_balance: data[:cash_balance],
      report_date: data[:report_date],
      institution_metadata: {
        "name" => "Interactive Brokers",
        "domain" => "interactivebrokers.com",
        "url" => "https://www.interactivebrokers.com",
        "color" => "#D32F2F"
      },
      raw_holdings_payload: Array(data[:open_positions]),
      raw_activities_payload: {
        "trades" => Array(data[:trades]),
        "cash_transactions" => Array(data[:cash_transactions])
      },
      raw_payload: data[:raw_payload] || {}
    )
  end
end
