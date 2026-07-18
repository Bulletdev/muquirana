class Assistant::Function::UpdateTag < Assistant::Function
  include Assistant::Function::Writable

  class << self
    def name
      "update_tag"
    end

    def description
      <<~INSTRUCTIONS
        Atualiza o nome ou a cor de uma tag existente.

        Identifique a tag pelo nome atual. Ao menos um entre new_name ou color deve ser
        informado. Use get_tags primeiro para confirmar que a tag existe.

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
          description: "Nome atual da tag a atualizar",
          enum: family_tag_names
        },
        new_name: {
          type: "string",
          description: "Novo nome da tag (opcional)"
        },
        color: {
          type: "string",
          description: "Nova cor em hexadecimal (opcional)"
        }
      }.merge(confirmation_property)
    )
  end

  def call(params = {})
    tag = family.tags.find_by(name: params["name"].to_s.strip)
    return error("not_found", "Tag '#{params["name"]}' nao encontrada.") unless tag

    attrs = {}
    attrs[:name] = params["new_name"].to_s.strip if params["new_name"].present?
    attrs[:color] = params["color"].to_s.strip if params["color"].present?

    return error("no_changes", "Informe ao menos um entre new_name ou color para atualizar.") if attrs.empty?

    tag.assign_attributes(attrs)
    return error("validation_failed", tag.errors.full_messages.join("; ")) unless tag.valid?

    unless confirmed?(params)
      return needs_confirmation(
        action: "update_tag",
        preview: serialize(tag),
        message: "Confirmar atualizacao da tag '#{tag.name}'?"
      )
    end

    if tag.save
      { success: true, tag: serialize(tag), message: "Tag atualizada." }
    else
      error("validation_failed", tag.errors.full_messages.join("; "))
    end
  end

  private
    def serialize(t)
      { id: t.id, name: t.name, color: t.color }
    end
end
