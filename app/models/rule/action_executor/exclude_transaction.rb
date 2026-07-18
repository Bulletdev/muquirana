class Rule::ActionExecutor::ExcludeTransaction < Rule::ActionExecutor
  def label
    I18n.t("rules.action_executors.exclude_transaction.label")
  end

  def execute(transaction_scope, value: nil, ignore_attribute_locks: false)
    scope = transaction_scope.with_entry

    unless ignore_attribute_locks
      # `excluded` lives on the entry, so we filter on the entry's locked_attributes
      scope = scope.where.not(
        Arel.sql("entries.locked_attributes ? 'excluded'")
      )
    end

    count_modified_resources(scope) do |txn|
      txn.entry.enrich_attribute(
        :excluded,
        true,
        source: "rule"
      )
    end
  end
end
