class Assistant::Function::UpdateCategory < Assistant::Function
  include Assistant::Function::Writable

  class << self
    def name
      "update_category"
    end

    def description
      <<~INSTRUCTIONS
        Atualiza o nome, a cor ou o icone de uma categoria existente.

        Use get_categories primeiro para achar o id da categoria. Ao menos um entre name,
        color ou icon deve ser informado. Mudar a cor de um pai nao propaga para as
        subcategorias existentes (a cor delas e definida na criacao).

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
      required: [ "id" ],
      properties: {
        id: {
          type: "string",
          description: "ID da categoria a atualizar (use get_categories para achar)"
        },
        name: {
          type: "string",
          description: "Novo nome da categoria (opcional)"
        },
        color: {
          type: "string",
          description: "Nova cor em hexadecimal (opcional)"
        },
        icon: {
          type: "string",
          description: "Novo nome de icone Lucide (opcional)"
        }
      }.merge(confirmation_property)
    )
  end

  def call(params = {})
    return error("not_found", "Categoria com id '#{params["id"]}' nao encontrada.") unless valid_uuid?(params["id"])
    category = family.categories.find_by(id: params["id"])
    return error("not_found", "Categoria com id '#{params["id"]}' nao encontrada.") unless category

    attrs = {}
    attrs[:name] = params["name"].to_s.strip if params["name"].present?
    attrs[:color] = params["color"].to_s.strip if params["color"].present?
    attrs[:lucide_icon] = params["icon"].to_s.strip if params["icon"].present?

    return error("no_changes", "Informe ao menos um entre name, color ou icon para atualizar.") if attrs.empty?

    category.assign_attributes(attrs)
    return error("validation_failed", category.errors.full_messages.join("; ")) unless category.valid?

    unless confirmed?(params)
      return needs_confirmation(
        action: "update_category",
        preview: serialize(category),
        message: "Confirmar atualizacao da categoria '#{full_name(category)}'?"
      )
    end

    if category.save
      { success: true, category: serialize(category), message: "Categoria '#{full_name(category)}' atualizada." }
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
