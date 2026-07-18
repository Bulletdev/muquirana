class Rule::ConditionFilter::TransactionType < Rule::ConditionFilter
  def label
    I18n.t("rules.condition_filters.transaction_type.label")
  end

  def type
    "select"
  end

  def options
    [
      [ I18n.t("rules.condition_filters.transaction_type.income"), "income" ],
      [ I18n.t("rules.condition_filters.transaction_type.expense"), "expense" ],
      [ I18n.t("rules.condition_filters.transaction_type.transfer"), "transfer" ]
    ]
  end

  def operators
    [ [ I18n.t("rules.condition_filters.transaction_type.equal_to"), "=" ] ]
  end

  def prepare(scope)
    scope.with_entry
  end

  def apply(scope, operator, value)
    # Logic mirrors Transaction::Search type filtering for consistency
    case value
    when "income"
      scope.where("entries.amount < 0")
           .where.not(kind: Transaction::TRANSFER_KINDS)
    when "expense"
      scope.where("entries.amount >= 0")
           .where.not(kind: Transaction::TRANSFER_KINDS)
    when "transfer"
      scope.where(kind: Transaction::TRANSFER_KINDS)
    else
      scope
    end
  end
end
