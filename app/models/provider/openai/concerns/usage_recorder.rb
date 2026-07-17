module Provider::Openai::Concerns::UsageRecorder
  extend ActiveSupport::Concern

  private
    # Grava uma linha de uso de LLM para a familia. E um SIDE-EFFECT: qualquer
    # falha e engolida (log) para NUNCA quebrar a chamada ao LLM que a originou.
    #
    # Aceita tanto o formato antigo (prompt_tokens/completion_tokens) quanto o
    # novo da OpenAI (input_tokens/output_tokens). Retorna nil quando nao ha
    # familia ou dados de uso.
    def record_usage(family:, model:, operation:, usage:, metadata: {})
      return unless family && usage

      usage = usage.to_h.stringify_keys

      prompt_tokens = (usage["prompt_tokens"] || usage["input_tokens"] || 0).to_i
      completion_tokens = (usage["completion_tokens"] || usage["output_tokens"] || 0).to_i
      total_tokens = (usage["total_tokens"] || (prompt_tokens + completion_tokens)).to_i

      estimated_cost = LlmUsage.calculate_cost(
        model: model,
        prompt_tokens: prompt_tokens,
        completion_tokens: completion_tokens
      )

      family.llm_usages.create!(
        provider: LlmUsage.infer_provider(model),
        model: model,
        operation: operation,
        prompt_tokens: prompt_tokens,
        completion_tokens: completion_tokens,
        total_tokens: total_tokens,
        estimated_cost: estimated_cost,
        metadata: metadata
      )

      Rails.logger.info("Uso de LLM registrado - operacao: #{operation}, custo: #{estimated_cost.inspect}")
    rescue => e
      Rails.logger.error("Falha ao registrar uso de LLM: #{e.message}")
      nil
    end
end
