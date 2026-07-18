class Rule::ConditionFilter::TransactionCategory < Rule::ConditionFilter
  def label
    I18n.t("rules.condition_filters.transaction_category.label")
  end

  def type
    "select"
  end

  def options
    family.categories.alphabetically.pluck(:name, :id)
  end

  def prepare(scope)
    scope.left_joins(:category)
  end

  def apply(scope, operator, value)
    expression = build_sanitized_where_condition("categories.id", operator, value)
    scope.where(expression)
  end
end
