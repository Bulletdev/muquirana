class RuleJob < ApplicationJob
  queue_as :medium_priority

  def perform(rule, ignore_attribute_locks: false, execution_type: "manual")
    executed_at = Time.current

    # Count matching resources before processing (queued count)
    transactions_queued = rule.affected_resource_count

    # Store the rule name at execution time so the audit trail persists even if
    # the rule is renamed or deleted later.
    rule_run = RuleRun.create!(
      rule: rule,
      rule_name: rule.name,
      execution_type: execution_type,
      status: "pending",
      transactions_queued: transactions_queued,
      transactions_processed: 0,
      transactions_modified: 0,
      pending_jobs_count: 0,
      executed_at: executed_at
    )

    begin
      transactions_modified = rule.apply(ignore_attribute_locks: ignore_attribute_locks)

      rule_run.update!(
        status: "success",
        transactions_processed: transactions_queued,
        transactions_modified: transactions_modified
      )
    rescue => e
      error_message = "#{e.class}: #{e.message}"
      Rails.logger.error("RuleJob failed for rule #{rule.id}: #{error_message}")

      rule_run.update(status: "failed", error_message: error_message)

      raise # Re-raise so the job is marked as failed
    end
  end
end
