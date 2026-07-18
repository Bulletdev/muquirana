class Assistant::Function::CreateCategory < Assistant::Function
  include Assistant::Function::Writable

  DEFAULT_ICON = "shopping-cart".freeze

  class << self
    def name
      "create_category"
    end

    def description
      <<~INSTRUCTIONS
        Cria uma nova categoria para a familia do usuario.

        Categorias tem no maximo dois niveis: uma categoria de nivel superior pode ter
        subcategorias, mas subcategorias nao podem ter filhas. Informe parent_id (obtido
        em get_categories) para criar uma subcategoria -- ela herda automaticamente a cor
        do pai.

        Se icon for omitido, um icone padrao e usado. Se color for omitido, uma cor da
        paleta e escolhida (ignorada em subcategorias, pois a cor e herdada). O nome da
        categoria deve ser unico na familia.

        Guard-rail: esta funcao so grava quando confirmed=true. Sem confirmacao, retorna
        apenas uma previa (requires_confirmation) para voce mostrar ao usuario.
      INSTRUCTIONS
    end
  end

  def strict_mode?
    false
  end

  def params_schema
    build_schema(
      required: [ "name" ],
      properties: {
        name: {
          type: "string",
          description: "Nome da categoria (unico dentro da familia)"
        },
        color: {
          type: "string",
          description: "Cor em hexadecimal (ex.: #e99537). Ignorada em subcategorias. Padrao: cor da paleta."
        },
        icon: {
          type: "string",
          description: "Nome do icone Lucide (ex.: 'shopping-cart'). Padrao usado se omitido."
        },
        parent_id: {
          type: "string",
          description: "ID de uma categoria de nivel superior existente para aninhar (torna esta uma subcategoria). Use get_categories para achar ids."
        }
      }.merge(confirmation_property)
    )
  end

  def call(params = {})
    name = params["name"].to_s.strip
    return error("name_required", "Informe um nome para a categoria.") if name.blank?

    color = params["color"].presence || Category::COLORS.sample
    icon = params["icon"].presence || DEFAULT_ICON
    attrs = { name: name, color: color, lucide_icon: icon }

    if params["parent_id"].present?
      return error("parent_not_found", "Categoria pai com id '#{params["parent_id"]}' nao encontrada.") unless valid_uuid?(params["parent_id"])
      parent = family.categories.find_by(id: params["parent_id"])
      return error("parent_not_found", "Categoria pai com id '#{params["parent_id"]}' nao encontrada.") unless parent
      attrs[:parent] = parent
    end

    category = family.categories.new(attrs)
    return error("validation_failed", category.errors.full_messages.join("; ")) unless category.valid?

    unless confirmed?(params)
      return needs_confirmation(
        action: "create_category",
        preview: serialize(category),
        message: "Confirmar criacao da categoria '#{full_name(category)}'?"
      )
    end

    if category.save
      { success: true, category: serialize(category), message: "Categoria '#{full_name(category)}' criada." }
    else
      error("validation_failed", category.errors.full_messages.join("; "))
    end
  end

  private
    def serialize(c)
      { id: c.id, name: c.name, name_with_parent: full_name(c), color: c.color, icon: c.lucide_icon, parent_id: c.parent_id }
    end

    def full_name(c)
      c.parent ? "#{c.parent.name} > #{c.name}" : c.name
    end
end
