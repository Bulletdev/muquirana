class Assistant::Function::GetTags < Assistant::Function
  class << self
    def name
      "get_tags"
    end

    def description
      <<~INSTRUCTIONS
        Retorna todas as tags definidas pela familia do usuario, em ordem alfabetica.

        Use quando o usuario quiser ver as tags disponiveis ou antes de referenciar
        uma tag em outra operacao, como create_tag ou update_tag.
      INSTRUCTIONS
    end
  end

  def call(params = {})
    tags = family.tags.alphabetically

    {
      tags: tags.map { |t| { id: t.id, name: t.name, color: t.color } },
      total: tags.size
    }
  end
end
