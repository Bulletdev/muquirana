require "net/http"
require "uri"
require "json"

# Cliente HTTP para um endpoint LLM externo self-hosted.
#
# PROTOCOLO: OpenAI-compativel /v1/chat/completions com stream via SSE. E o que
# o Ollama (porta OpenAI-compat) e o LM Studio expoem, e o formato que qualquer
# agente proprio pode falar facilmente. Cada evento SSE traz um JSON no formato
# chat.completion.chunk, do qual lemos choices[0].delta.content; o stream termina
# com "data: [DONE]".
#
# O endpoint NATIVO do Ollama (POST /api/chat) usa NDJSON (uma linha JSON por
# token, com message.content e done:true), formato DIFERENTE deste -- NAO e
# suportado aqui. Aponte para a porta OpenAI-compat (ex.: http://localhost:11434,
# que este cliente completa para /v1/chat/completions).
class Assistant::External::Client
  TIMEOUT_CONNECT = 10   # segundos
  TIMEOUT_READ    = 120  # segundos (modelo local pode demorar para raciocinar)
  MAX_RETRIES     = 2
  RETRY_DELAY     = 1    # segundos (dobra a cada tentativa)
  MAX_SSE_BUFFER  = 1_048_576 # 1 MB de teto no buffer de SSE

  # Caminho OpenAI-compat padrao, usado quando a URL informada nao tras um path
  # (ex.: usuario digita so http://localhost:11434).
  DEFAULT_PATH = "/v1/chat/completions"

  TRANSIENT_ERRORS = [
    Net::OpenTimeout,
    Net::ReadTimeout,
    Errno::ECONNREFUSED,
    Errno::ECONNRESET,
    Errno::EHOSTUNREACH,
    SocketError
  ].freeze

  def initialize(url:, token: nil, model: nil, agent_id: nil, session_key: nil)
    @url = normalize_url(url)
    @token = token # pipelock:ignore
    @model = model
    @agent_id = agent_id
    @session_key = session_key
  end

  # Faz stream de texto de um endpoint de chat OpenAI-compativel via SSE.
  #
  # messages - Array de hashes {role:, content:} (historico da conversa)
  # user     - Identificador opcional do usuario (persistencia de sessao)
  # block    - Chamado com cada pedaco de texto conforme chega
  #
  # Retorna o identificador do modelo devolvido pela resposta (ou nil).
  def chat(messages:, user: nil, &block)
    uri = URI(@url)
    request = build_request(uri, messages, user)
    retries = 0
    streaming_started = false

    begin
      http = build_http(uri)
      stream_response(http, request) do |content|
        streaming_started = true
        block.call(content)
      end
    rescue *TRANSIENT_ERRORS => e
      if streaming_started
        Rails.logger.warn("[External::Client] Stream interrompido: #{e.class} - #{e.message}")
        raise Assistant::Error, "A conexao com o assistente externo foi interrompida."
      end

      retries += 1
      if retries <= MAX_RETRIES
        Rails.logger.warn("[External::Client] Erro transiente (tentativa #{retries}/#{MAX_RETRIES}): #{e.class} - #{e.message}")
        sleep(RETRY_DELAY * retries)
        retry
      end
      Rails.logger.error("[External::Client] Inacessivel apos #{MAX_RETRIES + 1} tentativas: #{e.class} - #{e.message}")
      raise Assistant::Error, "O assistente externo esta temporariamente indisponivel."
    end
  end

  private
    # Aceita tanto a URL completa (.../v1/chat/completions) quanto so o host
    # (http://localhost:11434), completando o caminho OpenAI-compat neste caso.
    def normalize_url(url)
      uri = URI(url.to_s.strip)
      uri.path = DEFAULT_PATH if uri.path.blank? || uri.path == "/"
      uri.to_s
    rescue URI::InvalidURIError
      url
    end

    def stream_response(http, request, &block)
      model = nil
      buffer = +""
      done = false

      http.request(request) do |response|
        unless response.is_a?(Net::HTTPSuccess)
          Rails.logger.warn("[External::Client] HTTP #{response.code} do upstream: #{response.body.to_s.truncate(500)}")
          raise Assistant::Error, "O assistente externo respondeu HTTP #{response.code}."
        end

        response.read_body do |chunk|
          break if done
          buffer << chunk

          if buffer.bytesize > MAX_SSE_BUFFER
            raise Assistant::Error, "O stream do assistente externo passou do tamanho maximo de buffer."
          end

          while (line_end = buffer.index("\n"))
            line = buffer.slice!(0..line_end).strip
            next if line.empty?
            next unless line.start_with?("data:")

            data = line.delete_prefix("data:")
            data = data.delete_prefix(" ") # SSE: remove um espaco opcional

            if data == "[DONE]"
              done = true
              break
            end

            parsed = parse_sse_data(data)
            next unless parsed

            model ||= parsed["model"]
            content = parsed.dig("choices", 0, "delta", "content")
            block.call(content) unless content.nil?
          end
        end
      end

      model
    end

    def build_http(uri)
      proxy_uri = resolve_proxy(uri)

      http = if proxy_uri
        Net::HTTP.new(uri.host, uri.port, proxy_uri.host, proxy_uri.port, proxy_uri.user, proxy_uri.password)
      else
        Net::HTTP.new(uri.host, uri.port)
      end

      http.use_ssl = (uri.scheme == "https")
      http.open_timeout = TIMEOUT_CONNECT
      http.read_timeout = TIMEOUT_READ
      http
    end

    def resolve_proxy(uri)
      proxy_env = (uri.scheme == "https") ? "HTTPS_PROXY" : "HTTP_PROXY"
      proxy_url = ENV[proxy_env] || ENV[proxy_env.downcase]
      return nil if proxy_url.blank?

      no_proxy = ENV["NO_PROXY"] || ENV["no_proxy"]
      return nil if host_bypasses_proxy?(uri.host, no_proxy)

      URI(proxy_url)
    rescue URI::InvalidURIError => e
      Rails.logger.warn("[External::Client] URL de proxy invalida ignorada: #{e.message}")
      nil
    end

    def host_bypasses_proxy?(host, no_proxy)
      return false if no_proxy.blank?
      host_down = host.downcase
      no_proxy.split(",").any? do |pattern|
        pattern = pattern.strip.downcase.delete_prefix(".")
        host_down == pattern || host_down.end_with?(".#{pattern}")
      end
    end

    def build_request(uri, messages, user)
      request = Net::HTTP::Post.new(uri.request_uri)
      request["Content-Type"] = "application/json"
      request["Accept"] = "text/event-stream"
      # Token OPCIONAL: Ollama local nao exige autenticacao.
      request["Authorization"] = "Bearer #{@token}" if @token.present?
      # Headers para quem usa um agente proprio; Ollama/LM Studio ignoram.
      request["X-Agent-Id"] = @agent_id if @agent_id.present?
      request["X-Session-Key"] = @session_key if @session_key.present?

      payload = {
        # O campo model precisa casar com um modelo disponivel no endpoint
        # (ex.: "llama3.2" no Ollama). Cai no agent_id para um agente proprio.
        model: @model.presence || @agent_id.presence || "default",
        messages: messages,
        stream: true
      }
      payload[:user] = user if user.present?

      request.body = payload.to_json
      request
    end

    def parse_sse_data(data)
      JSON.parse(data)
    rescue JSON::ParserError => e
      Rails.logger.warn("[External::Client] SSE nao parseavel: #{e.message}")
      nil
    end
end
