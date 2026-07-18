module Family::CoinstatsConnectable
  extend ActiveSupport::Concern

  included do
    has_many :coinstats_items, dependent: :destroy
  end

  # CoinStats nao precisa de config global (a credencial e a chave OpenAPI do
  # proprio usuario, por item), entao a familia sempre pode iniciar uma conexao.
  def can_connect_coinstats?
    true
  end

  # Cria a conexao (guarda a chave OpenAPI). A carteira em si e vinculada depois,
  # via CoinstatsItemsController#link_wallet (endereco + chain), quando ja da para
  # popular o dropdown de chains com a chave salva.
  def create_coinstats_item!(api_key:, item_name: nil)
    coinstats_items.create!(
      name: item_name.presence || "CoinStats",
      api_key: api_key
    )
  end

  def has_coinstats_credentials?
    coinstats_items.active.any?
  end
end
