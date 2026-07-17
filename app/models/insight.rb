# Uma observacao proativa e tipada sobre as financas de uma familia, produzida
# a noite pelo GenerateInsightsJob. A logica financeira vive em
# Insight::Generators::*; o LLM (quando configurado) so escreve a prosa do
# `body` a partir de numeros pre-computados, entao as linhas sao seguras para
# renderizar como estao.
#
# Semantica de status: `read` e `dismissed` sao acoes do usuario; `expired` e do
# sistema -- marcado quando um sinal para de ser gerado (a condicao passou). Uma
# condicao que retorna reativa uma linha `expired`, mas nunca uma `dismissed`.
class Insight < ApplicationRecord
  belongs_to :family

  TYPES = %w[
    spending_anomaly
    cash_flow_warning
    net_worth_milestone
    subscription_audit
    savings_rate_change
    idle_cash
    budget_at_risk
    budget_on_track
  ].freeze

  enum :status, { active: "active", read: "read", dismissed: "dismissed", expired: "expired" }
  enum :priority, { high: "high", medium: "medium", low: "low" }, prefix: true

  validates :insight_type, presence: true, inclusion: { in: TYPES }
  validates :title, :body, :dedup_key, presence: true
  # Espelha o indice unico do banco para que chamadores diretos recebam erro de
  # validacao em vez de ActiveRecord::RecordNotUnique; corridas ainda batem no
  # indice.
  validates :dedup_key, uniqueness: { scope: :family_id }

  # Tudo que o usuario nao dispensou; o que o feed renderiza.
  scope :visible, -> { where(status: [ :active, :read ]) }
  scope :ordered, -> {
    order(Arel.sql("CASE insights.priority WHEN 'high' THEN 0 WHEN 'medium' THEN 1 ELSE 2 END"))
      .order(generated_at: :desc)
  }

  def mark_read!
    return unless active?

    update!(status: :read, read_at: Time.current)
  end

  def dismiss!
    update!(status: :dismissed, dismissed_at: Time.current)
  end

  # Desfaz uma dispensa sem re-marcar o insight como novo -- o usuario
  # obviamente ja o viu, entao ele volta como lido.
  def undismiss!
    update!(status: :read, dismissed_at: nil, read_at: read_at || Time.current)
  end
end
