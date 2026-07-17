# Escreve a prosa voltada ao usuario para um GeneratedInsight. O LLM age como
# redator, nao como raciocinador: recebe fatos pre-computados e so pode
# fraseia-los. Quando nenhum provider LLM esta configurado (comum em instalacoes
# self-hosted), ninguem na familia deu opt-in em IA, ou a chamada falha, usa-se o
# template i18n interpolado com os mesmos fatos, entao a geracao de insights
# nunca depende de um servico externo.
class Insight::BodyWriter
  SYSTEM_PROMPT = <<~PROMPT.freeze
    Voce escreve insights curtos para um app de financas pessoais.
    Regras:
    - Escreva 1-2 frases simples, dirigidas ao usuario como "voce".
    - Use apenas os fatos fornecidos. Nunca invente numeros, datas ou projecoes.
    - Repita valores monetarios exatamente como formatados nos fatos.
    - Sem conselho financeiro, sem jargao, sem emoji, sem pontos de exclamacao, sem listas ou titulos.
    - Responda apenas com as frases.
  PROMPT

  def initialize(family)
    @family = family
  end

  def write(generated_insight)
    llm_body(generated_insight) || template_body(generated_insight)
  end

  private
    attr_reader :family

    def template_body(generated_insight)
      I18n.t(
        "insights.templates.#{generated_insight.template_key}",
        **generated_insight.facts.symbolize_keys
      )
    end

    def llm_body(generated_insight)
      return nil unless provider

      prompt = <<~PROMPT
        Tipo de insight: #{generated_insight.insight_type.humanize}
        Fatos: #{generated_insight.facts.to_json}
      PROMPT

      response = provider.chat_response(
        prompt,
        model: llm_model,
        instructions: SYSTEM_PROMPT,
        family: family
      )
      return nil unless response.success?

      response.data.messages.filter_map(&:output_text).join(" ").strip.presence
    rescue => e
      Rails.logger.warn(
        "Insight::BodyWriter narration failed for family #{family.id} " \
        "(#{generated_insight.insight_type}): #{e.class}: #{e.message}"
      )
      nil
    end

    def llm_model
      Provider::Openai::MODELS.first
    end

    # Este job roda sem ser solicitado para cada familia, entao diferente do chat
    # (onde o usuario inicia cada chamada) a narracao por LLM depende de alguem
    # na familia ter IA habilitada -- consentimento para compartilhar dados
    # financeiros com o provider. Todos os demais recebem o body de template.
    def provider
      return @provider if defined?(@provider)
      return @provider = nil unless family.users.any?(&:ai_enabled?)

      @provider = Provider::Registry.for_concept(:llm).providers.compact.first
    end
end
