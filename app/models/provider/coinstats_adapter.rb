# Adapter do CoinStats para a fundacao generica de providers (AccountProvider).
#
# Com ele o CoinStats vira "so mais um provider": envolve qualquer
# CoinstatsAccount e expoe o contrato que a fundacao espera (provider_name, item,
# sync_path, institution_metadata, connection_configs). Mesmo caminho do
# Binance/Mercado Bitcoin -- nada precisou mudar na fundacao.
class Provider::CoinstatsAdapter < Provider::Base
  include Provider::Syncable

  # Registra este adapter para toda instancia de CoinstatsAccount.
  Provider::Factory.register("CoinstatsAccount", self)

  def self.supported_account_types
    %w[Crypto]
  end

  def self.connection_configs(family:)
    return [] unless family.can_connect_coinstats?

    [ {
      key: "coinstats",
      name: "CoinStats",
      description: "Conectar uma carteira on-chain via CoinStats",
      can_connect: true,
      new_account_path: ->(_accountable_type, _return_to) {
        Rails.application.routes.url_helpers.new_coinstats_item_path
      }
    } ]
  end

  def provider_name
    "coinstats"
  end

  # --- Provider::Syncable ------------------------------------------------------
  def item
    provider_account.coinstats_item
  end

  def sync_path
    Rails.application.routes.url_helpers.sync_coinstats_item_path(item)
  end

  def can_delete_holdings?
    false
  end

  # --- Metadados de instituicao (consumidos por Provider::Base#metadata) --------
  def institution_metadata
    meta = provider_account.institution_metadata || {}

    {
      name: meta["name"].presence || item&.institution_name,
      domain: meta["domain"].presence || item&.institution_domain,
      url: meta["url"].presence || item&.institution_url,
      color: meta["color"].presence || item&.institution_color,
      logo: meta["logo"].presence
    }
  end
end
