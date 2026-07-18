class IbkrItem::SyncCompleteEvent
  attr_reader :ibkr_item

  def initialize(ibkr_item)
    @ibkr_item = ibkr_item
  end

  def broadcast
    ibkr_item.accounts.each(&:broadcast_sync_complete)
    ibkr_item.family.broadcast_sync_complete
  end
end
