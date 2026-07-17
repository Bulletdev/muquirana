# frozen_string_literal: true

# Read-model de saude das conexoes de provider de uma familia (portado/adaptado
# do Sure, enxugado para os providers que o Muquirana suporta hoje: apenas Plaid).
#
# A estrutura PROVIDERS e reflexiva por design: adicionar uma nova integracao
# `*_items` aqui basta para ela aparecer no painel, sem reescrever a logica.
class ProviderConnectionStatus
  PROVIDERS = [
    { key: "plaid", type: "PlaidItem", association: :plaid_items, accounts: :plaid_accounts }
  ].freeze

  class << self
    def for_family(family)
      PROVIDERS.flat_map do |provider|
        next [] unless family.respond_to?(provider[:association])

        items = family.public_send(provider[:association]).ordered.to_a
        items.map { |item| new(provider, item).to_h }
      end
    end
  end

  def initialize(provider, item)
    @provider = provider
    @item = item
  end

  def to_h
    {
      id: item.id,
      provider: provider[:key],
      provider_type: provider[:type],
      name: item_value(:name, provider[:key].humanize),
      status: item_value(:status),
      requires_update: item_boolean(:requires_update?),
      scheduled_for_deletion: item_boolean(:scheduled_for_deletion?),
      institution: institution_payload,
      accounts: accounts_payload,
      syncing: item_boolean(:syncing?),
      created_at: item.created_at,
      updated_at: item.updated_at
    }
  end

  private

    attr_reader :provider, :item

    def institution_payload
      {
        name: item_value(:name, provider[:key].humanize),
        domain: item_value(:institution_domain),
        url: item_value(:institution_url)
      }
    end

    def accounts_payload
      records = provider_account_records
      total = records.size
      linked = records.count { |provider_account| linked_provider_account?(provider_account) }

      {
        total_count: total,
        linked_count: linked,
        unlinked_count: [ total - linked, 0 ].max
      }
    end

    def provider_account_records
      return [] unless item.respond_to?(provider[:accounts])

      @provider_account_records ||= item.public_send(provider[:accounts]).to_a
    end

    def linked_provider_account?(provider_account)
      return false unless provider_account.respond_to?(:account_provider)

      provider_account.account_provider.present?
    end

    def item_boolean(method_name)
      item_value(method_name, false) == true
    end

    def item_value(method_name, default = nil)
      return default unless item.respond_to?(method_name)

      item.public_send(method_name)
    end
end
