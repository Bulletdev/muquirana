# Adapter do Binance para a fundacao generica de providers (AccountProvider).
#
# Com ele o Binance vira "so mais um provider": envolve qualquer BinanceAccount e
# expoe o contrato que a fundacao espera (provider_name, item, sync_path,
# institution_metadata, connection_configs). Nada aqui foi preciso mudar na
# fundacao -- o Binance se plugou pelo mesmo caminho do Plaid.
#
# Alem disso inclui Provider::Configurable para declarar o host da API Spot,
# configuravel por Setting/ENV (BINANCE_SPOT_BASE_URL).
class Provider::BinanceAdapter < Provider::Base
  include Provider::Syncable
  include Provider::Configurable

  # Registra este adapter para toda instancia de BinanceAccount
  Provider::Factory.register("BinanceAccount", self)

  configure do
    description <<~DESC
      A Binance opera no BR com historico regulatorio instavel. Sua API-KEY pode
      precisar apontar para um host/escopo diferente do api.binance.com global.
    DESC

    field :spot_base_url,
          label: "URL base da API Spot",
          env_key: "BINANCE_SPOT_BASE_URL",
          default: Provider::Binance::DEFAULT_SPOT_BASE_URL,
          description: "Host da API Spot da Binance (Setting -> ENV -> default)"
  end

  # Host resolvido (Setting -> ENV -> default). Consumido por BinanceItem::Provided.
  def self.spot_base_url
    config_value(:spot_base_url).presence || Provider::Binance::DEFAULT_SPOT_BASE_URL
  end

  def self.supported_account_types
    %w[Crypto]
  end

  def self.connection_configs(family:)
    return [] unless family.can_connect_binance?

    [ {
      key: "binance",
      name: "Binance",
      description: "Conectar a uma carteira Binance",
      can_connect: true,
      new_account_path: ->(_accountable_type, _return_to) {
        Rails.application.routes.url_helpers.new_binance_item_path
      }
    } ]
  end

  def provider_name
    "binance"
  end

  # --- Provider::Syncable ------------------------------------------------------
  def item
    provider_account.binance_item
  end

  def sync_path
    Rails.application.routes.url_helpers.sync_binance_item_path(item)
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
      color: meta["color"].presence || item&.institution_color
    }
  end
end
