module IbkrItem::Provided
  extend ActiveSupport::Concern

  # Client do Flex Web Service construido com as credenciais deste item e o host
  # configuravel (Setting/ENV) resolvido pelo adapter. Retorna nil se faltar
  # credencial.
  def ibkr_provider
    return nil unless credentials_configured?

    @ibkr_provider ||= Provider::IbkrFlex.new(
      query_id: query_id,
      token: token,
      base_url: Provider::IbkrAdapter.base_url
    )
  end
end
