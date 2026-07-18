module Provider::Anthropic::Concerns::UsageRecorder
  extend ActiveSupport::Concern

  private
    # Grava uma linha de uso de LLM para a familia. E um SIDE-EFFECT: qualquer
    # falha e engolida (log) para NUNCA quebrar a chamada ao LLM que a originou.
    #
    # Recebe `usage` como Hash (input_tokens/output_tokens da Anthropic). O
    # provider ("anthropic") e inferido por LlmUsage.infer_provider a partir do
    # id do modelo (prefixo "claude"). Retorna nil sem familia ou sem uso.
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

      # Tokens de cache da Anthropic nao tem coluna dedicada; guardamos em
      # metadata quando presentes para nao perder o sinal de billing.
      cache_metadata = {}
      cache_metadata["cache_creation_input_tokens"] = usage["cache_creation_input_tokens"] if usage["cache_creation_input_tokens"]
      cache_metadata["cache_read_input_tokens"] = usage["cache_read_input_tokens"] if usage["cache_read_input_tokens"]

      family.llm_usages.create!(
        provider: LlmUsage.infer_provider(model),
        model: model,
        operation: operation,
        prompt_tokens: prompt_tokens,
        completion_tokens: completion_tokens,
        total_tokens: total_tokens,
        estimated_cost: estimated_cost,
        metadata: metadata.merge(cache_metadata)
      )

      Rails.logger.info("Uso de LLM registrado (anthropic) - operacao: #{operation}, custo: #{estimated_cost.inspect}")
    rescue => e
      Rails.logger.error("Falha ao registrar uso de LLM: #{e.message}")
      nil
    end
end
