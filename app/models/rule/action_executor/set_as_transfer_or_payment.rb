class Rule::ActionExecutor::SetAsTransferOrPayment < Rule::ActionExecutor
  def label
    I18n.t("rules.action_executors.set_as_transfer_or_payment.label")
  end

  def type
    "select"
  end

  def options
    family.accounts.alphabetically.pluck(:name, :id)
  end

  def execute(transaction_scope, value: nil, ignore_attribute_locks: false)
    target_account = family.accounts.find_by_id(value)
    return 0 unless target_account

    scope = transaction_scope.with_entry

    count_modified_resources(scope) do |txn|
      entry = txn.entry

      unless txn.transfer?
        transfer = build_transfer(target_account, entry)

        Transfer.transaction do
          transfer.save!

          # Determine the outflow kind from the destination (inflow) account,
          # matching Transfer::Creator behaviour.
          destination_account = transfer.inflow_transaction.entry.account
          outflow_kind = Transfer.kind_for_account(destination_account)

          transfer.outflow_transaction.update!(kind: outflow_kind)
          transfer.inflow_transaction.update!(kind: "funds_movement")
        end

        transfer.sync_account_later
      end
    end
  end

  private
    def build_transfer(target_account, entry)
      missing_transaction = Transaction.new(
        entry: target_account.entries.build(
          amount: entry.amount * -1,
          currency: entry.currency,
          date: entry.date,
          name: "#{target_account.liability? ? "Payment" : "Transfer"} #{entry.amount.negative? ? "to #{target_account.name}" : "from #{entry.account.name}"}"
        )
      )

      transfer = Transfer.find_or_initialize_by(
        inflow_transaction: entry.amount.positive? ? missing_transaction : entry.transaction,
        outflow_transaction: entry.amount.positive? ? entry.transaction : missing_transaction
      )
      transfer.status = "confirmed"
      transfer
    end
end
