# Compara a taxa de poupanca dos dois ultimos meses completos. O mes atual
# (parcial) e pulado de proposito -- a renda costuma cair no comeco ou fim do
# mes, o que torna taxas no meio do mes sem sentido. Os limiares sao em pontos
# percentuais, entao nao dependem da moeda -- nada a recalibrar para BRL.
class Insight::Generators::SavingsRateChangeGenerator < Insight::Generator
  produces "savings_rate_change"

  THRESHOLD_PP = 5
  HIGH_PRIORITY_PP = 10

  def generate
    last_month = last_month_period
    prior_start = last_month.start_date - 1.month
    prior_month = Period.custom(start_date: prior_start, end_date: last_month.start_date - 1.day)

    current_rate = savings_rate(last_month)
    previous_rate = savings_rate(prior_month)
    return [] unless current_rate && previous_rate

    delta = current_rate - previous_rate
    return [] if delta.abs < THRESHOLD_PP

    direction = delta.positive? ? "up" : "down"
    month_name = I18n.l(last_month.start_date, format: "%B")

    # "Voce poupou -5,4% da sua renda" e linguagem de maquina; uma taxa negativa
    # significa que a familia gastou mais do que ganhou, e o texto deve dizer
    # isso.
    template_key = if direction == "down" && current_rate.negative?
      "savings_rate_change.down_negative"
    else
      "savings_rate_change.#{direction}"
    end

    [
      build_insight(
        insight_type: "savings_rate_change",
        priority: delta.abs >= HIGH_PRIORITY_PP ? "high" : "medium",
        title: I18n.t("insights.titles.savings_rate_change.#{direction}", month: month_name),
        template_key: template_key,
        facts: {
          month: month_name,
          current_rate: signed_number(round(current_rate, 1)),
          previous_rate: signed_number(round(previous_rate, 1)),
          change_pp: round(delta.abs, 1)
        },
        metadata: {
          current_rate: round(current_rate, 1),
          previous_rate: round(previous_rate, 1)
        },
        period: last_month,
        dedup_key: "savings_rate_change:#{month_token(last_month.start_date)}"
      )
    ]
  end

  private
    def savings_rate(period)
      income = income_statement.income_totals(period: period).total.to_d
      return nil if income <= 0

      expense = income_statement.expense_totals(period: period).total.to_d
      (income - expense) / income * 100
    end
end
