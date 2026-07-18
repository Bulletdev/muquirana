module Transaction::Splittable
  extend ActiveSupport::Concern

  # Uma transacao so pode ser dividida se nao for parte de uma transferencia,
  # nao for ela mesma um pai/filho de split e nao estiver excluida.
  def splittable?
    !transfer? && !entry.split_child? && !entry.split_parent? && !entry.excluded?
  end
end
