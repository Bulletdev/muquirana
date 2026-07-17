class LlmUsage < ApplicationRecord
  belongs_to :family

  validates :provider, :model, :operation, presence: true
  validates :prompt_tokens, :completion_tokens, :total_tokens, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :estimated_cost, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  scope :for_family, ->(family) { where(family: family) }
  scope :for_operation, ->(operation) { where(operation: operation) }
  scope :recent, -> { order(created_at: :desc) }
  scope :for_date_range, ->(start_date, end_date) { where(created_at: start_date..end_date) }

  # Precos da OpenAI por 1M de tokens (USD).
  # O Muquirana so chama a OpenAI, entao o mapa fica enxuto: apenas os modelos
  # que o app realmente usa (familia gpt-4.1 nas chamadas de chat / PDF /
  # auto-categorize) mais os gpt-4o como fallback comum. As linhas de Anthropic,
  # Google e os modelos ficticios gpt-5.x do fork foram removidos.
  # Fonte: https://platform.openai.com/docs/pricing
  PRICING = {
    "openai" => {
      "gpt-4.1" => { prompt: 2.00, completion: 8.00 },
      "gpt-4.1-mini" => { prompt: 0.40, completion: 1.60 },
      "gpt-4.1-nano" => { prompt: 0.10, completion: 0.40 },
      "gpt-4o" => { prompt: 2.50, completion: 10.00 },
      "gpt-4o-mini" => { prompt: 0.15, completion: 0.60 }
    }
  }.freeze

  # Calcula o custo estimado para um modelo e um consumo de tokens.
  # Retorna nil quando nao ha preco conhecido (modelo custom/self-hosted).
  def self.calculate_cost(model:, prompt_tokens:, completion_tokens:)
    pricing = find_pricing("openai", model)

    unless pricing
      Rails.logger.info("Sem preco para o modelo: #{model}")
      return nil
    end

    # Precos sao por 1M de tokens.
    prompt_cost = (prompt_tokens * pricing[:prompt]) / 1_000_000.0
    completion_cost = (completion_tokens * pricing[:completion]) / 1_000_000.0

    (prompt_cost + completion_cost).round(6)
  end

  # Localiza o preco de um modelo, com suporte a prefixo. Ordena por prefixo
  # mais longo primeiro para que um snapshot (ex.: "gpt-4.1-mini-2026-03-17")
  # nao case com a familia mais ampla ("gpt-4.1") antes da linha especifica.
  def self.find_pricing(provider, model)
    return nil unless PRICING.key?(provider)

    provider_pricing = PRICING[provider]
    return provider_pricing[model] if provider_pricing.key?(model)

    provider_pricing.sort_by { |model_prefix, _pricing| -model_prefix.length }.each do |model_prefix, pricing|
      return pricing if model.to_s.start_with?(model_prefix)
    end

    nil
  end

  # O Muquirana so integra a OpenAI, entao o provider e sempre "openai".
  def self.infer_provider(_model)
    "openai"
  end

  # Estatisticas agregadas para uma familia.
  def self.statistics_for_family(family, start_date: nil, end_date: nil)
    scope = for_family(family)
    scope = scope.for_date_range(start_date, end_date) if start_date && end_date

    # Custos so consideram linhas com custo estimado.
    scope_with_cost = scope.where.not(estimated_cost: nil)

    requests_with_cost = scope_with_cost.count
    total_cost = scope_with_cost.sum(:estimated_cost).to_f.round(2)
    avg_cost = requests_with_cost > 0 ? (total_cost / requests_with_cost).round(4) : 0.0

    {
      total_requests: scope.count,
      requests_with_cost: requests_with_cost,
      total_prompt_tokens: scope.sum(:prompt_tokens),
      total_completion_tokens: scope.sum(:completion_tokens),
      total_tokens: scope.sum(:total_tokens),
      total_cost: total_cost,
      avg_cost: avg_cost,
      by_operation: scope_with_cost.group(:operation).sum(:estimated_cost).transform_values { |v| v.to_f.round(2) },
      by_model: scope_with_cost.group(:model).sum(:estimated_cost).transform_values { |v| v.to_f.round(2) }
    }
  end

  # Custo formatado na moeda da familia (pt-BR: R$ ...). Retorna nil quando nao
  # ha custo estimado, para o chamador exibir "N/A".
  def formatted_cost
    return nil if estimated_cost.nil?

    Money.new(estimated_cost, family.currency).format
  end

  def failed?
    metadata.present? && metadata["error"].present?
  end

  def http_status_code
    metadata&.dig("http_status_code")
  end

  def error_message
    metadata&.dig("error")
  end
end
