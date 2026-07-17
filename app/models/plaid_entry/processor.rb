class PlaidEntry::Processor
  # plaid_transaction is the raw hash fetched from Plaid API and converted to JSONB
  def initialize(plaid_transaction, plaid_account:, category_matcher:)
    @plaid_transaction = plaid_transaction
    @plaid_account = plaid_account
    @category_matcher = category_matcher
  end

  def process
    PlaidAccount.transaction do
      # O Plaid agora e "so mais um provider": a escrita passa pela fundacao
      # generica (Account::ProviderImportAdapter), ganhando a dedup cross-source.
      entry = import_adapter.import_transaction(
        external_id: plaid_id,
        source: "plaid",
        amount: amount,
        currency: currency,
        date: date,
        name: name,
        category_id: matched_category_id,
        merchant: merchant
      )

      # Mantem a coluna legada `plaid_id` populada para os caminhos que ainda a
      # usam (webhook, investments/liabilities, delete de transacao removida e
      # Entry#linked?).
      entry.update_column(:plaid_id, plaid_id) if entry.plaid_id != plaid_id

      entry
    end
  end

  private
    attr_reader :plaid_transaction, :plaid_account, :category_matcher

    def import_adapter
      @import_adapter ||= Account::ProviderImportAdapter.new(account)
    end

    def account
      plaid_account.account
    end

    def matched_category_id
      return nil unless detailed_category

      category_matcher.match(detailed_category)&.id
    end

    def plaid_id
      plaid_transaction["transaction_id"]
    end

    def name
      plaid_transaction["merchant_name"] || plaid_transaction["original_description"]
    end

    def amount
      plaid_transaction["amount"]
    end

    def currency
      plaid_transaction["iso_currency_code"]
    end

    def date
      plaid_transaction["date"]
    end

    def detailed_category
      plaid_transaction.dig("personal_finance_category", "detailed")
    end

    def merchant
      merchant_id = plaid_transaction["merchant_entity_id"]
      merchant_name = plaid_transaction["merchant_name"]

      return nil unless merchant_id.present? && merchant_name.present?

      ProviderMerchant.find_or_create_by!(
        source: "plaid",
        name: merchant_name,
      ) do |m|
        m.provider_merchant_id = merchant_id
        m.website_url = plaid_transaction["website"]
        m.logo_url = plaid_transaction["logo_url"]
      end
    end
end
