# Adapter da Interactive Brokers para a fundacao generica de providers
# (AccountProvider).
#
# Com ele a IBKR vira "so mais um provider": envolve qualquer IbkrAccount e expoe
# o contrato que a fundacao espera (provider_name, item, sync_path,
# institution_metadata, connection_configs). Nada aqui foi preciso mudar na
# fundacao -- a IBKR se plugou pelo mesmo caminho do Plaid, da Binance e do
# Mercado Bitcoin.
#
# Inclui Provider::Configurable para declarar o host do Flex Web Service,
# configuravel por Setting/ENV (IBKR_FLEX_BASE_URL).
class Provider::IbkrAdapter < Provider::Base
  include Provider::Syncable
  include Provider::Configurable

  # Registra este adapter para toda instancia de IbkrAccount
  Provider::Factory.register("IbkrAccount", self)

  configure do
    description <<~DESC
      A Interactive Brokers exporta posicoes e trades via Flex Web Service. A
      conexao usa o par query_id + token de uma Flex Query da propria conta.
    DESC

    field :base_url,
          label: "URL base do Flex Web Service",
          env_key: "IBKR_FLEX_BASE_URL",
          default: Provider::IbkrFlex::DEFAULT_BASE_URL,
          description: "Host do Flex Web Service da IBKR (Setting -> ENV -> default)"
  end

  # Host resolvido (Setting -> ENV -> default). Consumido por IbkrItem::Provided.
  def self.base_url
    config_value(:base_url).presence || Provider::IbkrFlex::DEFAULT_BASE_URL
  end

  def self.supported_account_types
    %w[Investment]
  end

  def self.connection_configs(family:)
    return [] unless family.can_connect_ibkr?

    [ {
      key: "ibkr",
      name: "Interactive Brokers",
      description: "Conectar a uma conta Interactive Brokers via Flex Query",
      can_connect: true,
      new_account_path: ->(_accountable_type, _return_to) {
        Rails.application.routes.url_helpers.new_ibkr_item_path
      }
    } ]
  end

  def provider_name
    "ibkr"
  end

  # --- Provider::Syncable ------------------------------------------------------
  def item
    provider_account.ibkr_item
  end

  def sync_path
    Rails.application.routes.url_helpers.sync_ibkr_item_path(item)
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
