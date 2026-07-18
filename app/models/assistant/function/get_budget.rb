class Assistant::Function::GetBudget < Assistant::Function
  include ActiveSupport::NumberHelper

  MAX_PRIOR_MONTHS = 11

  class << self
    def name
      "get_budget"
    end

    def description
      <<~INSTRUCTIONS
        Use para ver como o usuario esta em relacao ao orcamento mensal -- total
        orcado x gasto e um detalhamento por categoria/subcategoria, como na tela de
        orcamento.

        Ideal para perguntas como:
        - Como estou em relacao ao meu orcamento este mes?
        - Em quais categorias estou estourando o orcamento?
        - Como o gasto deste mes se compara aos ultimos meses?

        Parametros:
        - `month` (opcional): "YYYY-MM" ou "MMM-YYYY". Padrao: o mes atual.
        - `prior_months` (opcional): inteiro de 0 a #{MAX_PRIOR_MONTHS}. Numero de meses
          anteriores ao mes-alvo a incluir para comparacao. Padrao 0.

        Exemplo (apenas o mes atual):

        ```
        get_budget({})
        ```

        Exemplo (mes atual mais os 2 meses anteriores):

        ```
        get_budget({ month: "#{Date.current.strftime('%Y-%m')}", prior_months: 2 })
        ```
      INSTRUCTIONS
    end
  end

  def strict_mode?
    false
  end

  def params_schema
    build_schema(
      properties: {
        month: {
          type: "string",
          description: "Mes-alvo no formato YYYY-MM ou MMM-YYYY. Padrao: mes atual."
        },
        prior_months: {
          type: "integer",
          description: "Numero de meses antes do mes-alvo a retornar para comparacao.",
          minimum: 0,
          maximum: MAX_PRIOR_MONTHS
        }
      }
    )
  end

  def call(params = {})
    target_start = resolve_month_start(params["month"])
    prior = params["prior_months"].to_i.clamp(0, MAX_PRIOR_MONTHS)

    month_starts = (0..prior).map { |offset| (target_start << offset) }.reverse
    requested = month_starts.count { |start_date| Budget.budget_date_valid?(start_date, family: family) }

    months = month_starts.filter_map do |start_date|
      next unless Budget.budget_date_valid?(start_date, family: family)
      build_month_payload(start_date, bootstrap: start_date == target_start)
    end

    result = {
      currency: family.currency,
      months: months
    }
    unavailable = requested - months.length
    result[:months_unavailable] = unavailable if unavailable > 0
    result
  end

  private
    def build_month_payload(start_date, bootstrap:)
      budget = if bootstrap
        Budget.find_or_bootstrap(family, start_date: start_date)
      else
        family.budgets.find_by(start_date: start_date.beginning_of_month, end_date: start_date.end_of_month)
      end
      return nil unless budget

      groups = BudgetCategory::Group.for(budget.budget_categories)

      {
        month: budget.to_param,
        period: {
          start_date: budget.start_date,
          end_date: budget.end_date
        },
        is_current: budget.current?,
        initialized: budget.initialized?,
        totals: {
          budgeted_spending: format_money(budget.budgeted_spending),
          allocated_spending: format_money(budget.allocated_spending),
          available_to_allocate: format_money(budget.available_to_allocate),
          actual_spending: format_money(budget.actual_spending),
          available_to_spend: format_money(budget.available_to_spend),
          percent_of_budget_spent: format_percent(budget.initialized? ? budget.percent_of_budget_spent : 0),
          overage_percent: format_percent(budget.overage_percent)
        },
        income: {
          expected_income: format_money(budget.expected_income),
          actual_income: format_money(budget.actual_income),
          remaining_expected_income: format_money((budget.expected_income || 0) - budget.actual_income)
        },
        categories: groups.map { |group| serialize_group(group) }
      }
    end

    def serialize_group(group)
      parent = group.budget_category
      serialize_category(parent).merge(
        color: parent.category.color,
        subcategories: group.budget_subcategories.map { |sub| serialize_category(sub) }
      )
    end

    def serialize_category(bc)
      {
        name: bc.name,
        budgeted: format_money(bc.budgeted_spending),
        actual: format_money(bc.actual_spending),
        available: format_money(bc.available_to_spend),
        percent_spent: format_percent(bc.budgeted_spending.to_f > 0 ? bc.percent_of_budget_spent : 0),
        status: category_status(bc)
      }
    end

    def category_status(bc)
      return "no_activity" if bc.actual_spending.to_f.zero?
      return "over_budget" if bc.available_to_spend.negative?
      "on_track"
    end

    def resolve_month_start(raw)
      (parse_month(raw) || Date.current).beginning_of_month
    end

    def parse_month(raw)
      return nil if raw.blank?

      # Date.strptime ignora sufixos, entao validamos o formato com ancoras antes.
      fmt = case raw
      when /\A\d{4}-\d{2}\z/         then "%Y-%m"
      when /\A[A-Za-z]{3}-\d{4}\z/   then "%b-%Y"
      end

      raise Assistant::Error, "Mes invalido: #{raw}. Use YYYY-MM ou MMM-YYYY." if fmt.nil?

      Date.strptime(raw, fmt)
    rescue ArgumentError
      raise Assistant::Error, "Mes invalido: #{raw}. Use YYYY-MM ou MMM-YYYY."
    end

    def format_money(value)
      Money.new(value || 0, family.currency).format
    end

    def format_percent(value)
      number_to_percentage(value || 0, precision: 1)
    end
end
