module Family::BinanceConnectable
  extend ActiveSupport::Concern

  included do
    has_many :binance_items, dependent: :destroy
  end

  # Binance nao precisa de config global (a credencial e por usuario/item), entao
  # a familia sempre pode iniciar uma conexao.
  def can_connect_binance?
    true
  end

  def create_binance_item!(api_key:, api_secret:, item_name: nil)
    item = binance_items.create!(
      name: item_name.presence || "Binance",
      api_key: api_key,
      api_secret: api_secret
    )
    item.sync_later
    item
  end

  def has_binance_credentials?
    binance_items.active.any?
  end
end
