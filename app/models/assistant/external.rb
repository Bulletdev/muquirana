# US-08: Assistente externo self-hosted.
#
# Aponta o assistente de IA para um endpoint LLM proprio do usuario -- Ollama,
# LM Studio ou um agente proprio -- para que os dados financeiros nunca saiam da
# maquina. Forte para o pilar self-hosted/privacidade.
#
# Protocolo suportado: OpenAI-compativel /v1/chat/completions com stream via SSE
# (o mesmo que Ollama e LM Studio expoem). O endpoint NATIVO do Ollama
# (POST /api/chat, NDJSON) NAO e suportado -- use a porta OpenAI-compat, que os
# dois servidores oferecem por padrao. Ver Assistant::External::Client.
#
# Diferente do fluxo padrao (Assistant + Provider::Openai, que usa a Responses
# API e as tools locais get_transactions/get_accounts/...), o assistente externo
# NAO executa as funcoes locais: ele conversa com base no historico + nas
# instrucoes do sistema. Um agente proprio que queira ler os dados do usuario faz
# isso do seu lado. Isso e intencional: tool-calling estilo OpenAI com modelos
# locais e fragil e depende do modelo.
class Assistant::External
  include Assistant::Broadcastable

  Config = Struct.new(:url, :token, :model, :agent_id, :session_key, keyword_init: true)

  # Quantas mensagens da conversa mandamos como contexto. Modelos locais costumam
  # ter janela de contexto menor que a da OpenAI, entao limitamos.
  MAX_CONVERSATION_MESSAGES = 20

  attr_reader :chat

  class << self
    def for_chat(chat)
      new(chat)
    end

    # Configurado = tem URL. O token e OPCIONAL de proposito: um Ollama local
    # nao exige autenticacao. Quando a URL esta em branco, Assistant.for_chat
    # cai no fluxo normal (OpenAI).
    def configured?
      config.url.present?
    end

    def config
      Config.new(
        url: ENV["EXTERNAL_ASSISTANT_URL"].presence || Setting.external_assistant_url.presence,
        token: ENV["EXTERNAL_ASSISTANT_TOKEN"].presence || Setting.external_assistant_token.presence,
        model: ENV["EXTERNAL_ASSISTANT_MODEL"].presence || Setting.external_assistant_model.presence,
        # agent_id/session_key sao passados como headers opcionais para quem usa
        # um agente proprio; Ollama e LM Studio simplesmente os ignoram.
        agent_id: ENV["EXTERNAL_ASSISTANT_AGENT_ID"].presence || Setting.external_assistant_agent_id.presence,
        session_key: ENV["EXTERNAL_ASSISTANT_SESSION_KEY"].presence
      )
    end
  end

  def initialize(chat)
    @chat = chat
  end

  def respond_to(message)
    config = self.class.config

    assistant_message = AssistantMessage.new(
      chat: chat,
      content: "",
      ai_model: config.model.presence || "external"
    )

    client = build_client(config)
    messages = build_conversation_messages(message)

    returned_model = client.chat(
      messages: messages,
      user: "muquirana-family-#{chat.user.family_id}"
    ) do |text|
      stop_thinking if assistant_message.content.blank?
      assistant_message.append_text!(text)
    end

    if assistant_message.content.blank?
      raise Assistant::Error, "O assistente externo devolveu uma resposta vazia."
    end

    assistant_message.update!(ai_model: returned_model) if returned_model.present?
  rescue => e
    stop_thinking
    cleanup_partial_response(assistant_message)
    chat.add_error(e)
  end

  private
    def build_client(config)
      Assistant::External::Client.new(
        url: config.url,
        token: config.token,
        model: config.model,
        agent_id: config.agent_id,
        session_key: config.session_key
      )
    end

    # Historico enviado ao endpoint. A instrucao do sistema (identidade, regras,
    # idioma pt-BR, moeda) vem do mesmo config_for do fluxo padrao, para que o
    # modelo local se comporte como o assistente da Muquirana.
    def build_conversation_messages(message)
      system_prompt = Assistant.config_for(chat)[:instructions]

      history = chat.conversation_messages
                    .where(status: "complete")
                    .ordered
                    .last(MAX_CONVERSATION_MESSAGES)
                    .map { |msg| { role: msg.role, content: msg.content } }

      # A UserMessage que disparou este turno ainda esta "pending" (o
      # AssistantResponseJob roda no after_create_commit), entao nao entra no
      # historico "complete" acima -- incluimos ela explicitamente.
      history << { role: "user", content: message.content } unless history.any? { |m| m[:content] == message.content && m[:role] == "user" }

      messages = []
      messages << { role: "system", content: system_prompt } if system_prompt.present?
      messages.concat(history)
      messages
    end

    def cleanup_partial_response(assistant_message)
      assistant_message&.destroy! if assistant_message&.persisted?
    rescue ActiveRecord::ActiveRecordError => e
      Rails.logger.warn("[Assistant::External] Falha ao limpar resposta parcial: #{e.message}")
    end
end
