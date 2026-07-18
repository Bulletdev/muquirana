module MercadoBitcoinItem::Provided
  extend ActiveSupport::Concern

  # Client de API construido com as credenciais deste item e o host configuravel
  # (Setting/ENV) resolvido pelo adapter. Retorna nil se as credenciais faltam.
  def mercado_bitcoin_provider
    return nil unless credentials_configured?

    @mercado_bitcoin_provider ||= Provider::MercadoBitcoin.new(
      api_key: api_key,
      api_secret: api_secret,
      base_url: Provider::MercadoBitcoinAdapter.base_url
    )
  end
end
