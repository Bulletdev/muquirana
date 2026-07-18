# Le o orcamento vigente da familia (se houver) e produz ou um alerta --
# categorias que estouraram ou estao perto do limite -- ou, uma vez que o mes ja
# passou da metade, um sinal positivo discreto de que esta tudo no rumo. Os
# checks de saude (estouro/perto do limite) sao derivados aqui a partir dos
# numeros crus do BudgetCategory, ja que o modelo do Muquirana nao expoe esses
# helpers.
class Insight::Generators::BudgetInsightGenerator < Insight::Generator
  produces "budget_at_risk", "budget_on_track"

  # Percentuais, entao independem de moeda: nao ha o que recalibrar para BRL.
  NEAR_LIMIT_PCT = 90    # perto do limite a partir de 90% do orcamento da categoria
  ON_TRACK_MIN_ELAPSED = 0.5 # sinal positivo so depois que o mes passa da metade
  MAX_LISTED_CATEGORIES = 3

  def generate
    budget = current_budget
    return [] unless budget&.initialized?

    parent_categories = budget.budget_categories.reject(&:subcategory?)
    over = parent_categories.select { |bc| budgeted?(bc) && over_budget?(bc) }
    near = parent_categories.select { |bc| budgeted?(bc) && near_limit?(bc) }

    if over.any? || near.any?
      [ at_risk_insight(budget, over, near) ]
    elsif on_track_eligible?(budget, parent_categories)
      [ on_track_insight(budget) ]
    else
      []
    end
  end

  private
    def current_budget
      family.budgets
        .includes(budget_categories: :category)
        .where("start_date <= ? AND end_date >= ?", Date.current, Date.current)
        .first
    end

    # Um orcamento de categoria so conta se recebeu alocacao positiva.
    def budgeted?(budget_category)
      budget_category.budgeted_spending.to_d.positive?
    end

    # available_to_spend = budgeted_spending - actual_spending; negativo = estouro.
    def over_budget?(budget_category)
      budget_category.available_to_spend.negative?
    end

    def near_limit?(budget_category)
      !over_budget?(budget_category) && budget_category.percent_of_budget_spent >= NEAR_LIMIT_PCT
    end

    def at_risk_insight(budget, over, near)
      flagged = over + near
      category_names = flagged.first(MAX_LISTED_CATEGORIES).map { |bc| bc.category.name }

      build_insight(
        insight_type: "budget_at_risk",
        priority: over.any? ? "high" : "medium",
        title: I18n.t("insights.titles.budget_at_risk", count: flagged.size),
        template_key: over.any? ? "budget_at_risk.over" : "budget_at_risk.near",
        facts: {
          categories: category_names.to_sentence,
          count: flagged.size,
          budget_spent_pct: round(budget.percent_of_budget_spent, 0).to_i
        },
        # O balde de percentual mantem o body fresco conforme o uso geral se move
        # (uma virada de >=10 pontos reescreve) sem a agitacao noturna de um ponto.
        metadata: {
          over_category_ids: over.map { |bc| bc.category.id }.sort,
          near_category_ids: near.map { |bc| bc.category.id }.sort,
          budget_spent_pct_bucket: (round(budget.percent_of_budget_spent, 0).to_i / 10) * 10
        },
        period: budget.period,
        dedup_key: "budget_at_risk:#{month_token(budget.start_date)}"
      )
    end

    def on_track_insight(budget)
      build_insight(
        insight_type: "budget_on_track",
        priority: "low",
        title: I18n.t("insights.titles.budget_on_track"),
        template_key: "budget_on_track",
        facts: {
          spent: format_money(budget.actual_spending),
          budgeted: format_money(budget.budgeted_spending),
          budget_spent_pct: round(budget.percent_of_budget_spent, 0).to_i
        },
        # Baldeado para amortecer a agitacao noturna: um movimento de um ponto nao
        # deve contar como mudanca material que reescreve o body ou ressuscita uma
        # dispensa.
        metadata: {
          budget_spent_pct_bucket: (round(budget.percent_of_budget_spent, 0).to_i / 10) * 10
        },
        period: budget.period,
        dedup_key: "budget_on_track:#{month_token(budget.start_date)}"
      )
    end

    def on_track_eligible?(budget, parent_categories)
      return false unless parent_categories.any? { |bc| budgeted?(bc) }

      total_days = (budget.end_date - budget.start_date).to_i + 1
      elapsed_days = (Date.current - budget.start_date).to_i + 1

      elapsed_days.to_f / total_days >= ON_TRACK_MIN_ELAPSED
    end
end
