class Rule::ConditionFilter::TransactionAccount < Rule::ConditionFilter
  def label
    I18n.t("rules.condition_filters.transaction_account.label")
  end

  def type
    "select"
  end

  def options
    family.accounts.alphabetically.pluck(:name, :id)
  end

  def apply(scope, operator, value)
    expression = build_sanitized_where_condition("entries.account_id", operator, value)
    scope.where(expression)
  end
end
