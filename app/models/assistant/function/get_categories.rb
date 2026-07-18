class Assistant::Function::GetCategories < Assistant::Function
  class << self
    def name
      "get_categories"
    end

    def description
      <<~INSTRUCTIONS
        Retorna todas as categorias da familia do usuario, em ordem alfabetica.

        Cada item traz id, name, name_with_parent (ex.: "Alimentacao > Restaurantes"),
        color, icon, parent_id (nulo para categorias de nivel superior) e is_subcategory.
        Use esta funcao antes de criar subcategorias ou de referenciar uma categoria
        pelo id em update_category.
      INSTRUCTIONS
    end
  end

  def call(params = {})
    categories = family.categories.includes(:parent).alphabetically.to_a
    categories.sort_by! { |c| name_with_parent(c).downcase }

    {
      categories: categories.map { |c|
        {
          id: c.id,
          name: c.name,
          name_with_parent: name_with_parent(c),
          color: c.color,
          icon: c.lucide_icon,
          parent_id: c.parent_id,
          is_subcategory: c.subcategory?
        }
      },
      total: categories.size
    }
  end

  private
    def name_with_parent(category)
      category.parent ? "#{category.parent.name} > #{category.name}" : category.name
    end
end
