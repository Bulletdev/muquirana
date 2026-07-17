class BinanceItemsController < ApplicationController
  before_action :set_binance_item, only: %i[destroy sync]

  def new
    @binance_item = Current.family.binance_items.build
  end

  def create
    @binance_item = Current.family.create_binance_item!(
      api_key: binance_item_params[:api_key],
      api_secret: binance_item_params[:api_secret],
      item_name: binance_item_params[:name]
    )

    redirect_to accounts_path, notice: t(".success")
  rescue ActiveRecord::RecordInvalid => e
    @binance_item = e.record
    render :new, status: :unprocessable_entity
  end

  def destroy
    @binance_item.destroy_later
    redirect_to accounts_path, notice: t(".success")
  end

  def sync
    @binance_item.sync_later unless @binance_item.syncing?

    respond_to do |format|
      format.html { redirect_back_or_to accounts_path }
      format.json { head :ok }
    end
  end

  private
    def set_binance_item
      @binance_item = Current.family.binance_items.find(params[:id])
    end

    def binance_item_params
      params.require(:binance_item).permit(:name, :api_key, :api_secret)
    end
end
