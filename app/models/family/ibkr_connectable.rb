module Family::IbkrConnectable
  extend ActiveSupport::Concern

  included do
    has_many :ibkr_items, dependent: :destroy
  end

  # A IBKR nao precisa de config global (a credencial e por usuario/item: query_id
  # + token de uma Flex Query), entao a familia sempre pode iniciar uma conexao.
  def can_connect_ibkr?
    true
  end

  def create_ibkr_item!(query_id:, token:, item_name: nil)
    item = ibkr_items.create!(
      name: item_name.presence || "Interactive Brokers",
      query_id: query_id,
      token: token
    )
    item.sync_later
    item
  end

  def has_ibkr_credentials?
    ibkr_items.active.any?
  end
end
