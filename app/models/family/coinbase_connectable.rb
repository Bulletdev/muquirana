module Family::CoinbaseConnectable
  extend ActiveSupport::Concern

  included do
    has_many :coinbase_items, dependent: :destroy
  end

  # Coinbase nao precisa de config global (a credencial e por usuario/item), entao
  # a familia sempre pode iniciar uma conexao.
  def can_connect_coinbase?
    true
  end

  def create_coinbase_item!(api_key:, api_secret:, item_name: nil)
    item = coinbase_items.create!(
      name: item_name.presence || "Coinbase",
      api_key: api_key,
      api_secret: api_secret
    )
    item.sync_later
    item
  end

  def has_coinbase_credentials?
    coinbase_items.active.any?
  end
end
