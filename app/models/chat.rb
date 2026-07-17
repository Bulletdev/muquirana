class Chat < ApplicationRecord
  include Debuggable

  belongs_to :user

  has_one :viewer, class_name: "User", foreign_key: :last_viewed_chat_id, dependent: :nullify # "Last chat user has viewed"
  has_many :messages, dependent: :destroy

  validates :title, presence: true

  scope :ordered, -> { order(created_at: :desc) }

  class << self
    def start!(prompt, model:)
      create!(
        title: generate_title(prompt),
        messages: [ UserMessage.new(content: prompt, ai_model: model) ]
      )
    end

    def generate_title(prompt)
      prompt.first(80)
    end
  end

  def needs_assistant_response?
    conversation_messages.ordered.last.role != "assistant"
  end

  def retry_last_message!
    update!(error: nil)

    last_message = conversation_messages.ordered.last

    if last_message.present? && last_message.role == "user"

      ask_assistant_later(last_message)
    end
  end

  def update_latest_response!(provider_response_id)
    update!(latest_assistant_response_id: provider_response_id)
  end

  def add_error(e)
    update! error: e.to_json
    broadcast_append target: "messages", partial: "chats/error", locals: { chat: self }
  end

  # A mensagem legivel do erro, para a tela.
  #
  # O `error` e jsonb, mas `add_error` grava `e.to_json` -- uma STRING JSON
  # dentro do jsonb. Entao o que volta daqui e String, nao Hash. O metodo
  # aceita os dois para nao depender desse detalhe.
  #
  # So a `message` sai daqui. O `details` pode trazer o corpo inteiro da
  # resposta da API e fica atras do AI_DEBUG_MODE.
  def error_message
    return nil if error.blank?

    dados = error.is_a?(String) ? JSON.parse(error) : error
    # Erro conhecido vira frase limpa em pt-BR (ver friendly_ai_error). Se nao
    # reconhecer, cai na mensagem crua do provedor -- melhor mostrar algo do
    # que nada. O corpo completo continua atras do modo debug.
    friendly_ai_error(dados) || dados["message"].presence
  rescue JSON::ParserError, TypeError
    # Erro gravado num formato que nao reconhecemos nao pode derrubar a tela do
    # chat: a pessoa perde o motivo, mas ve o aviso generico e o "tentar de
    # novo", que e o que tinha antes.
    nil
  end

  def clear_error
    update! error: nil
    broadcast_remove target: "chat-error"
  end

  def assistant
    @assistant ||= Assistant.for_chat(self)
  end

  def ask_assistant_later(message)
    clear_error
    AssistantResponseJob.perform_later(message)
  end

  def ask_assistant(message)
    assistant.respond_to(message)
  end

  def conversation_messages
    if debug_mode?
      messages
    else
      messages.where(type: [ "UserMessage", "AssistantMessage" ])
    end
  end

  private
    # Traduz os erros conhecidos do provedor de IA para uma frase limpa, em
    # pt-BR e com o que fazer. O texto cru da OpenAI (ingles, com URL e codigo
    # do tipo "(insufficient_quota)") continua no modo debug -- aqui ele so
    # atrapalharia quem usa.
    #
    # Casa por CODIGO quando o corpo da resposta veio em `details`, e por texto
    # quando so sobrou a mensagem do Faraday. `insufficient_quota` e um 429,
    # entao vem ANTES do rate limit generico, senao a cota esgotada viraria
    # "espere alguns segundos" (conselho errado: esperar nao devolve a cota).
    def friendly_ai_error(dados)
      sinal = "#{dados["message"]} #{dados["details"]}".downcase

      chave =
        if sinal.include?("insufficient_quota") || sinal.include?("exceeded your current quota")
          "quota"
        elsif sinal.include?("invalid_api_key") || sinal.include?("incorrect api key") || sinal.include?("invalid authentication")
          "invalid_key"
        elsif sinal.include?("rate limit") || sinal.include?("rate_limit")
          "rate_limit"
        elsif sinal.include?("does not exist") || sinal.include?("model_not_found")
          "model"
        elsif sinal.include?("timeout") || sinal.include?("timed out") || sinal.include?("failed to open tcp") || sinal.include?("connection")
          "network"
        end

      chave && I18n.t("chats.error.reasons.#{chave}")
    end
end
