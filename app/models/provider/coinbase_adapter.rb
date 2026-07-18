# Adapter do Coinbase para a fundacao generica de providers (AccountProvider).
#
# Com ele o Coinbase vira "so mais um provider": envolve qualquer CoinbaseAccount
# e expoe o contrato que a fundacao espera (provider_name, item, sync_path,
# institution_metadata, connection_configs). Nada aqui foi preciso mudar na
# fundacao -- o Coinbase se plugou pelo mesmo caminho do Plaid, da Binance e do
# Mercado Bitcoin.
#
# Inclui Provider::Configurable para declarar o host da API, configuravel por
# Setting/ENV (COINBASE_API_BASE_URL) -- util para apontar a um mock em teste.
class Provider::CoinbaseAdapter < Provider::Base
  include Provider::Syncable
  include Provider::Configurable

  # Registra este adapter para toda instancia de CoinbaseAccount
  Provider::Factory.register("CoinbaseAccount", self)

  configure do
    description <<~DESC
      A Coinbase opera no BR normalmente. A conexao usa uma chave CDP (Coinbase
      Developer Platform) da propria conta do usuario: um par de nome da chave +
      chave privada EC, colados e usados somente para leitura de carteiras.
    DESC

    field :api_base_url,
          label: "URL base da API",
          env_key: "COINBASE_API_BASE_URL",
          default: Provider::Coinbase::DEFAULT_API_BASE_URL,
          description: "Host da API da Coinbase (Setting -> ENV -> default)"
  end

  # Host resolvido (Setting -> ENV -> default). Consumido por CoinbaseItem::Provided.
  def self.api_base_url
    config_value(:api_base_url).presence || Provider::Coinbase::DEFAULT_API_BASE_URL
  end

  def self.supported_account_types
    %w[Crypto]
  end

  def self.connection_configs(family:)
    return [] unless family.can_connect_coinbase?

    [ {
      key: "coinbase",
      name: "Coinbase",
      description: "Conectar a uma carteira Coinbase",
      can_connect: true,
      new_account_path: ->(_accountable_type, _return_to) {
        Rails.application.routes.url_helpers.new_coinbase_item_path
      }
    } ]
  end

  def provider_name
    "coinbase"
  end

  # --- Provider::Syncable ------------------------------------------------------
  def item
    provider_account.coinbase_item
  end

  def sync_path
    Rails.application.routes.url_helpers.sync_coinbase_item_path(item)
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
