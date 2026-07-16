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
    dados["message"].presence
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
end
