# Dynamic settings the user can change within the app (helpful for self-hosting)
class Setting < RailsSettings::Base
  cache_prefix { "v1" }

  field :synth_api_key, type: :string, default: ENV["SYNTH_API_KEY"]
  field :openai_access_token, type: :string, default: ENV["OPENAI_ACCESS_TOKEN"]

  field :require_invite_for_signup, type: :boolean, default: false
  field :require_email_confirmation, type: :boolean, default: ENV.fetch("REQUIRE_EMAIL_CONFIRMATION", "true") == "true"

  # Host da API Spot da Binance. A Binance opera no BR com historico regulatorio
  # instavel; a key do usuario pode apontar para um host/escopo diferente do
  # api.binance.com global. Lido tambem por Provider::Configurable (Setting ->
  # ENV BINANCE_SPOT_BASE_URL -> default). Default nil aqui para que a cadeia de
  # fallback do Provider::Configurable seja a fonte da verdade.
  field :binance_spot_base_url, type: :string, default: nil

  # Host da API do Mercado Bitcoin (exchange brasileira). Lido por
  # Provider::Configurable (Setting -> ENV MERCADO_BITCOIN_BASE_URL -> default).
  # Default nil aqui para que a cadeia de fallback do Provider::Configurable seja
  # a fonte da verdade.
  field :mercado_bitcoin_base_url, type: :string, default: nil
end
