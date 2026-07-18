class Assistant::Function::CreateTag < Assistant::Function
  include Assistant::Function::Writable

  class << self
    def name
      "create_tag"
    end

    def description
      <<~INSTRUCTIONS
        Cria uma nova tag para a familia do usuario.

        Tags sao aplicadas a transacoes para organiza-las alem das categorias. Se color
        for omitido, uma cor da paleta padrao e escolhida. O nome da tag deve ser unico
        na familia.

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
          description: "Nome da tag (unico dentro da familia)"
        },
        color: {
          type: "string",
          description: "Cor em hexadecimal (ex.: #e99537). Se omitido, uma cor da paleta padrao e escolhida."
        }
      }.merge(confirmation_property)
    )
  end

  def call(params = {})
    name = params["name"].to_s.strip
    return error("name_required", "Informe um nome para a tag.") if name.blank?

    color = params["color"].presence || Tag::COLORS.sample
    tag = family.tags.new(name: name, color: color)
    return error("validation_failed", tag.errors.full_messages.join("; ")) unless tag.valid?

    unless confirmed?(params)
      return needs_confirmation(
        action: "create_tag",
        preview: serialize(tag),
        message: "Confirmar criacao da tag '#{tag.name}'?"
      )
    end

    if tag.save
      { success: true, tag: serialize(tag), message: "Tag '#{tag.name}' criada." }
    else
      error("validation_failed", tag.errors.full_messages.join("; "))
    end
  end

  private
    def serialize(t)
      { id: t.id, name: t.name, color: t.color }
    end
end
