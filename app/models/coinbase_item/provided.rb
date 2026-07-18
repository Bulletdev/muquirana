module CoinbaseItem::Provided
  extend ActiveSupport::Concern

  # Client de API construido com as credenciais CDP deste item e o host
  # configuravel (Setting/ENV) resolvido pelo adapter. Retorna nil se as
  # credenciais faltam.
  def coinbase_provider
    return nil unless credentials_configured?

    @coinbase_provider ||= Provider::Coinbase.new(
      api_key: api_key,
      api_secret: api_secret,
      api_base_url: Provider::CoinbaseAdapter.api_base_url
    )
  end
end
