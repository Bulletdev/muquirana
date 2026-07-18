class CoinstatsItem::SyncCompleteEvent
  attr_reader :coinstats_item

  def initialize(coinstats_item)
    @coinstats_item = coinstats_item
  end

  def broadcast
    coinstats_item.accounts.each(&:broadcast_sync_complete)
    coinstats_item.family.broadcast_sync_complete
  end
end
