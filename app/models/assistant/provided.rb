module Assistant::Provided
  extend ActiveSupport::Concern

  # Resolve o provider LLM para a conversa levando em conta QUEM e o usuario:
  #   1. chave propria do usuario (BYOK)                 -> usa a chave dele
  #   2. senao, chave da instancia:
  #        - admin: sempre
  #        - membro: so se o admin liberou E dentro do teto de custo mensal
  #   3. senao -> bloqueia com mensagem acionavel (surge como erro no chat)
  def get_model_provider(ai_model)
    user = chat.user
    provider_name = provider_name_for(ai_model)

    own = user_provider(provider_name, user.own_ai_key_for(provider_name), ai_model)
    return own if own

    if user.can_use_instance_ai?
      # compact: providers nao configurados (sem chave) vem como nil.
      instance = registry.providers.compact.find { |provider| provider.supports_model?(ai_model) }
      return instance if instance

      raise Assistant::Error, I18n.t("assistant.access.no_instance_key")
    end

    raise Assistant::Error, ai_access_denied_message(user)
  end

  private
    def registry
      @registry ||= Provider::Registry.for_concept(:llm)
    end

    def provider_name_for(ai_model)
      ai_model.to_s.start_with?("claude") ? :anthropic : :openai
    end

    # Monta um provider com a chave PROPRIA do usuario (ou nil se ele nao tem
    # chave, ou se a chave dele nao cobre o modelo pedido).
    def user_provider(provider_name, token, ai_model)
      return nil if token.blank?

      provider = case provider_name
      when :openai then Provider::Openai.new(token)
      when :anthropic then Provider::Anthropic.new(token, model: Provider::Anthropic.effective_model)
      end

      provider if provider&.supports_model?(ai_model)
    end

    def ai_access_denied_message(user)
      if Setting.family_members_can_use_ai && user.ai_monthly_cost_used.to_f.positive?
        I18n.t("assistant.access.quota_exceeded")
      else
        I18n.t("assistant.access.no_access")
      end
    end
end
