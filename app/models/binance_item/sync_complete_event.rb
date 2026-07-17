class BinanceItem::SyncCompleteEvent
  attr_reader :binance_item

  def initialize(binance_item)
    @binance_item = binance_item
  end

  def broadcast
    binance_item.accounts.each(&:broadcast_sync_complete)
    binance_item.family.broadcast_sync_complete
  end
end
