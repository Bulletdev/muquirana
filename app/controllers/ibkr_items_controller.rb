class IbkrItemsController < ApplicationController
  before_action :set_ibkr_item, only: %i[destroy sync]

  def new
    @ibkr_item = Current.family.ibkr_items.build
  end

  def create
    @ibkr_item = Current.family.create_ibkr_item!(
      query_id: ibkr_item_params[:query_id],
      token: ibkr_item_params[:token],
      item_name: ibkr_item_params[:name]
    )

    redirect_to accounts_path, notice: t(".success")
  rescue ActiveRecord::RecordInvalid => e
    @ibkr_item = e.record
    render :new, status: :unprocessable_entity
  end

  def destroy
    @ibkr_item.destroy_later
    redirect_to accounts_path, notice: t(".success")
  end

  def sync
    @ibkr_item.sync_later unless @ibkr_item.syncing?

    respond_to do |format|
      format.html { redirect_back_or_to accounts_path }
      format.json { head :ok }
    end
  end

  private
    def set_ibkr_item
      @ibkr_item = Current.family.ibkr_items.find(params[:id])
    end

    def ibkr_item_params
      params.require(:ibkr_item).permit(:name, :query_id, :token)
    end
end
