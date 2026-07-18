class SplitsController < ApplicationController
  before_action :set_entry

  def new
    @categories = Current.family.categories.alphabetically
  end

  def create
    unless @entry.transaction.splittable?
      redirect_back_or_to transactions_path, alert: t("splits.create.not_splittable")
      return
    end

    @entry.split!(build_splits)
    @entry.sync_account_later

    redirect_back_or_to transactions_path, notice: t("splits.create.success")
  rescue ActiveRecord::RecordInvalid => e
    redirect_back_or_to transactions_path, alert: e.message
  end

  def edit
    resolve_to_parent!

    unless @entry.split_parent?
      redirect_to transactions_path, alert: t("splits.edit.not_split")
      return
    end

    @categories = Current.family.categories.alphabetically
    @children = @entry.child_entries.includes(:entryable)
  end

  def update
    resolve_to_parent!

    unless @entry.split_parent?
      redirect_to transactions_path, alert: t("splits.edit.not_split")
      return
    end

    Entry.transaction do
      @entry.unsplit!
      @entry.split!(build_splits)
    end

    @entry.sync_account_later

    redirect_to transactions_path, notice: t("splits.update.success")
  rescue ActiveRecord::RecordInvalid => e
    redirect_to transactions_path, alert: e.message
  end

  def destroy
    resolve_to_parent!

    unless @entry.split_parent?
      redirect_to transactions_path, alert: t("splits.edit.not_split")
      return
    end

    @entry.unsplit!
    @entry.sync_account_later

    redirect_to transactions_path, notice: t("splits.destroy.success")
  end

  private
    # Isolamento multi-tenant: parte sempre de Current.family. Nao ha camada de
    # permissao por conta neste app (diferente do repo de origem).
    def set_entry
      @entry = Current.family.entries.find(params[:transaction_id])
    end

    def resolve_to_parent!
      @entry = @entry.parent_entry if @entry.split_child?
    end

    # O usuario informa magnitudes positivas. Cada filha herda o sinal do pai
    # (despesa positiva / receita negativa), garantindo que a soma bata com o
    # valor do pai.
    def build_splits
      sign = @entry.amount.negative? ? -1 : 1

      raw_splits = split_params[:splits]
      raw_splits = raw_splits.values if raw_splits.respond_to?(:values)

      raw_splits.map do |s|
        {
          name: s[:name],
          amount: s[:amount].to_d.abs * sign,
          category_id: s[:category_id].presence,
          excluded: s[:excluded]
        }
      end
    end

    def split_params
      params.require(:split).permit(splits: [ :name, :amount, :category_id, :excluded ])
    end
end
