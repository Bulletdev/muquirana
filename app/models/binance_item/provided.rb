module BinanceItem::Provided
  extend ActiveSupport::Concern

  # Client de API construido com as credenciais deste item e o host configuravel
  # (Setting/ENV) resolvido pelo adapter. Retorna nil se as credenciais faltam.
  def binance_provider
    return nil unless credentials_configured?

    @binance_provider ||= Provider::Binance.new(
      api_key: api_key,
      api_secret: api_secret,
      spot_base_url: Provider::BinanceAdapter.spot_base_url
    )
  end
end
