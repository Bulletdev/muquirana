module CoinstatsItem::Provided
  extend ActiveSupport::Concern

  # Client de API construido com a chave OpenAPI deste item. Retorna nil se a
  # credencial faltar.
  def coinstats_provider
    return nil unless credentials_configured?

    @coinstats_provider ||= Provider::Coinstats.new(api_key: api_key)
  end
end
