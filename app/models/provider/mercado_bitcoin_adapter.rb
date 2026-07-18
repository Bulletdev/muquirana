# Adapter do Mercado Bitcoin para a fundacao generica de providers
# (AccountProvider).
#
# Com ele o Mercado Bitcoin vira "so mais um provider": envolve qualquer
# MercadoBitcoinAccount e expoe o contrato que a fundacao espera (provider_name,
# item, sync_path, institution_metadata, connection_configs). Nada aqui foi
# preciso mudar na fundacao -- o Mercado Bitcoin se plugou pelo mesmo caminho do
# Plaid e da Binance.
#
# Inclui Provider::Configurable para declarar o host da TAPI, configuravel por
# Setting/ENV (MERCADO_BITCOIN_BASE_URL).
class Provider::MercadoBitcoinAdapter < Provider::Base
  include Provider::Syncable
  include Provider::Configurable

  # Registra este adapter para toda instancia de MercadoBitcoinAccount
  Provider::Factory.register("MercadoBitcoinAccount", self)

  configure do
    description <<~DESC
      O Mercado Bitcoin e uma exchange brasileira e opera em BRL nativamente.
      A conexao usa a API-KEY (TAPI) da propria conta do usuario.
    DESC

    field :base_url,
          label: "URL base da API",
          env_key: "MERCADO_BITCOIN_BASE_URL",
          default: Provider::MercadoBitcoin::DEFAULT_BASE_URL,
          description: "Host da API do Mercado Bitcoin (Setting -> ENV -> default)"
  end

  # Host resolvido (Setting -> ENV -> default). Consumido por MercadoBitcoinItem::Provided.
  def self.base_url
    config_value(:base_url).presence || Provider::MercadoBitcoin::DEFAULT_BASE_URL
  end

  def self.supported_account_types
    %w[Crypto]
  end

  def self.connection_configs(family:)
    return [] unless family.can_connect_mercado_bitcoin?

    [ {
      key: "mercado_bitcoin",
      name: "Mercado Bitcoin",
      description: "Conectar a uma conta Mercado Bitcoin",
      can_connect: true,
      new_account_path: ->(_accountable_type, _return_to) {
        Rails.application.routes.url_helpers.new_mercado_bitcoin_item_path
      }
    } ]
  end

  def provider_name
    "mercado_bitcoin"
  end

  # --- Provider::Syncable ------------------------------------------------------
  def item
    provider_account.mercado_bitcoin_item
  end

  def sync_path
    Rails.application.routes.url_helpers.sync_mercado_bitcoin_item_path(item)
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
