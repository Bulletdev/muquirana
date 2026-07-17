class RecurringTransactionsController < ApplicationController
  layout "settings"

  before_action :set_recurring_transaction, only: %i[toggle_status destroy]

  def index
    @recurring_transactions = Current.family.recurring_transactions
                                    .includes(:merchant)
                                    .order(status: :asc, next_expected_date: :asc)
    @family = Current.family
  end

  # Criacao manual a partir de uma transacao existente.
  def create
    transaction = Current.family.transactions.find(params[:transaction_id])
    RecurringTransaction.create_from_transaction(transaction)

    flash[:notice] = t("recurring_transactions.created")
    redirect_back fallback_location: recurring_transactions_path
  end

  def identify
    count = RecurringTransaction.identify_patterns_for!(Current.family)

    flash[:notice] = t("recurring_transactions.identified", count: count)
    redirect_to recurring_transactions_path
  end

  def cleanup
    count = RecurringTransaction.cleanup_stale_for(Current.family)

    flash[:notice] = t("recurring_transactions.cleaned_up", count: count)
    redirect_to recurring_transactions_path
  end

  def toggle_status
    if @recurring_transaction.active?
      @recurring_transaction.mark_inactive!
      message = t("recurring_transactions.marked_inactive")
    else
      @recurring_transaction.mark_active!
      message = t("recurring_transactions.marked_active")
    end

    flash[:notice] = message
    redirect_to recurring_transactions_path
  end

  def destroy
    @recurring_transaction.destroy!

    flash[:notice] = t("recurring_transactions.deleted")
    redirect_to recurring_transactions_path
  end

  private
    def set_recurring_transaction
      @recurring_transaction = Current.family.recurring_transactions.find(params[:id])
    end
end
