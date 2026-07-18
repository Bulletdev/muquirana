class CoinbaseItemsController < ApplicationController
  before_action :set_coinbase_item, only: %i[destroy sync]

  def new
    @coinbase_item = Current.family.coinbase_items.build
  end

  def create
    @coinbase_item = Current.family.create_coinbase_item!(
      api_key: coinbase_item_params[:api_key],
      api_secret: coinbase_item_params[:api_secret],
      item_name: coinbase_item_params[:name]
    )

    redirect_to accounts_path, notice: t(".success")
  rescue ActiveRecord::RecordInvalid => e
    @coinbase_item = e.record
    render :new, status: :unprocessable_entity
  end

  def destroy
    @coinbase_item.destroy_later
    redirect_to accounts_path, notice: t(".success")
  end

  def sync
    @coinbase_item.sync_later unless @coinbase_item.syncing?

    respond_to do |format|
      format.html { redirect_back_or_to accounts_path }
      format.json { head :ok }
    end
  end

  private
    def set_coinbase_item
      @coinbase_item = Current.family.coinbase_items.find(params[:id])
    end

    def coinbase_item_params
      params.require(:coinbase_item).permit(:name, :api_key, :api_secret)
    end
end
