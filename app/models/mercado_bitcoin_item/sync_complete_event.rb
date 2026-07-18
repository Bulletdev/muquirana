class MercadoBitcoinItem::SyncCompleteEvent
  attr_reader :mercado_bitcoin_item

  def initialize(mercado_bitcoin_item)
    @mercado_bitcoin_item = mercado_bitcoin_item
  end

  def broadcast
    mercado_bitcoin_item.accounts.each(&:broadcast_sync_complete)
    mercado_bitcoin_item.family.broadcast_sync_complete
  end
end
