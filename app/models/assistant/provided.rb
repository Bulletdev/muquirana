module Assistant::Provided
  extend ActiveSupport::Concern

  def get_model_provider(ai_model)
    # compact: providers nao configurados (sem chave) vem como nil. Sem isso,
    # com so a chave Anthropic setada (openai => nil), o nil vem antes na lista
    # e `nil.supports_model?` estouraria antes de achar o provider certo.
    registry.providers.compact.find { |provider| provider.supports_model?(ai_model) }
  end

  private
    def registry
      @registry ||= Provider::Registry.for_concept(:llm)
    end
end
