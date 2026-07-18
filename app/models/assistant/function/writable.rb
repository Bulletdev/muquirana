# Mixin das tools de ESCRITA do assistente.
#
# Guard-rail: nenhuma escrita e aplicada sem confirmacao explicita. Toda tool de
# escrita expoe o parametro booleano `confirmed`. Enquanto ele nao for `true`, a
# tool valida a operacao e devolve apenas uma PREVIA (`requires_confirmation`),
# sem gravar nada. O assistente deve mostrar a previa ao usuario e so reenviar a
# chamada com `confirmed: true` depois que o usuario confirmar. Assim o modelo
# nao altera dados da familia por conta propria.
module Assistant::Function::Writable
  extend ActiveSupport::Concern

  UUID_REGEX = /\A[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\z/

  private
    def confirmed?(params)
      params["confirmed"] == true
    end

    # Propriedade `confirmed` a ser mesclada no params_schema de cada tool.
    def confirmation_property
      {
        confirmed: {
          type: "boolean",
          description: "Envie true APENAS depois que o usuario confirmar. Se ausente ou false, a funcao retorna somente uma previa (requires_confirmation) e NADA e gravado no banco."
        }
      }
    end

    def needs_confirmation(action:, preview:, message:)
      {
        requires_confirmation: true,
        action: action,
        preview: preview,
        message: message
      }
    end

    def valid_uuid?(str)
      str.to_s.match?(UUID_REGEX)
    end

    def error(key, message, extras = {})
      { success: false, error: key, message: message }.merge(extras)
    end
end
