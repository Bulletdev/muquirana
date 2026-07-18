# Dynamic settings the user can change within the app (helpful for self-hosting)
class Setting < RailsSettings::Base
  cache_prefix { "v1" }

  field :synth_api_key, type: :string, default: ENV["SYNTH_API_KEY"]
  field :openai_access_token, type: :string, default: ENV["OPENAI_ACCESS_TOKEN"]

  # US-07: chave e modelo Anthropic (Claude). "IA opcional, chave propria" -- o
  # usuario informa a propria chave. Default nil para que a cadeia
  # ENV -> Setting -> DEFAULT_MODEL do provider seja a fonte da verdade.
  field :anthropic_access_token, type: :string, default: ENV["ANTHROPIC_ACCESS_TOKEN"]
  field :anthropic_model, type: :string, default: nil

  # US-08: Assistente externo self-hosted. Aponta o assistente de IA para um
  # endpoint LLM proprio do usuario (Ollama, LM Studio, agente proprio) para que
  # os dados financeiros nao saiam da maquina. Enquanto a URL estiver em branco,
  # o assistente cai no fluxo normal (Provider::Openai). Default nil aqui para
  # que a cadeia ENV -> Setting em Assistant::External.config seja a fonte da
  # verdade (mesmo padrao de binance_spot_base_url / mercado_bitcoin_base_url).
  field :external_assistant_url, type: :string, default: nil
  field :external_assistant_token, type: :string, default: nil
  field :external_assistant_model, type: :string, default: nil
  field :external_assistant_agent_id, type: :string, default: nil

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
