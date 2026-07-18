class CoinbaseItem::SyncCompleteEvent
  attr_reader :coinbase_item

  def initialize(coinbase_item)
    @coinbase_item = coinbase_item
  end

  def broadcast
    coinbase_item.accounts.each(&:broadcast_sync_complete)
    coinbase_item.family.broadcast_sync_complete
  end
end
