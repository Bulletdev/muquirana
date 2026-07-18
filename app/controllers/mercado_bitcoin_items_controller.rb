class MercadoBitcoinItemsController < ApplicationController
  before_action :set_mercado_bitcoin_item, only: %i[destroy sync]

  def new
    @mercado_bitcoin_item = Current.family.mercado_bitcoin_items.build
  end

  def create
    @mercado_bitcoin_item = Current.family.create_mercado_bitcoin_item!(
      api_key: mercado_bitcoin_item_params[:api_key],
      api_secret: mercado_bitcoin_item_params[:api_secret],
      item_name: mercado_bitcoin_item_params[:name]
    )

    redirect_to accounts_path, notice: t(".success")
  rescue ActiveRecord::RecordInvalid => e
    @mercado_bitcoin_item = e.record
    render :new, status: :unprocessable_entity
  end

  def destroy
    @mercado_bitcoin_item.destroy_later
    redirect_to accounts_path, notice: t(".success")
  end

  def sync
    @mercado_bitcoin_item.sync_later unless @mercado_bitcoin_item.syncing?

    respond_to do |format|
      format.html { redirect_back_or_to accounts_path }
      format.json { head :ok }
    end
  end

  private
    def set_mercado_bitcoin_item
      @mercado_bitcoin_item = Current.family.mercado_bitcoin_items.find(params[:id])
    end

    def mercado_bitcoin_item_params
      params.require(:mercado_bitcoin_item).permit(:name, :api_key, :api_secret)
    end
end
