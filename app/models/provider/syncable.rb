# Modulo para adapters cujo provider suporta sync com servicos externos.
module Provider::Syncable
  extend ActiveSupport::Concern

  # Caminho para sincronizar o item deste provider
  def sync_path
    raise NotImplementedError, "#{self.class} must implement #sync_path"
  end

  # Objeto item/conexao do provider (ex.: PlaidItem)
  def item
    raise NotImplementedError, "#{self.class} must implement #item"
  end

  def syncing?
    item&.syncing? || false
  end

  def status
    item&.status
  end

  def requires_update?
    status == "requires_update"
  end
end
