module Family::MercadoBitcoinConnectable
  extend ActiveSupport::Concern

  included do
    has_many :mercado_bitcoin_items, dependent: :destroy
  end

  # Mercado Bitcoin nao precisa de config global (a credencial e por
  # usuario/item), entao a familia sempre pode iniciar uma conexao.
  def can_connect_mercado_bitcoin?
    true
  end

  def create_mercado_bitcoin_item!(api_key:, api_secret:, item_name: nil)
    item = mercado_bitcoin_items.create!(
      name: item_name.presence || "Mercado Bitcoin",
      api_key: api_key,
      api_secret: api_secret
    )
    item.sync_later
    item
  end

  def has_mercado_bitcoin_credentials?
    mercado_bitcoin_items.active.any?
  end
end
