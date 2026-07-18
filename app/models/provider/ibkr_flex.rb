# Client de baixo nivel do Flex Web Service da Interactive Brokers.
#
# Nao e OAuth nem tempo real: o investidor gera uma "Flex Query" no painel da
# IBKR e cola aqui o par (query_id + token). O fluxo tem dois passos:
#
#   1. SendRequest  -> a IBKR enfileira a geracao do extrato e devolve um
#      ReferenceCode.
#   2. GetStatement -> baixa o XML pelo ReferenceCode. Enquanto o extrato ainda
#      esta sendo gerado a IBKR responde com um codigo transitorio (1003/1004/
#      1019); fazemos POLLING com backoff ate ficar pronto ou estourar o limite.
#
# Nao confundir com `Provider::IbkrAdapter` (o adapter da fundacao de contas) nem
# com a classe base `Provider`. Aqui e so o HTTP client.
#
# A logica de porte veio do Provider::IbkrFlex do Sure (we-promise/sure, AGPLv3),
# reescrita sobre FARADAY (o Muquirana nao usa HTTParty) e com os erros tipados
# traduzidos pela camada de sync em mensagem acionavel em pt-BR.
#
# Endpoint (confirmado por curl em 2026-07-18, HTTP 200 em ambos os hosts): o
# canonico atual e gdcdyn/Universal/servlet/FlexStatementService, com os metodos
# SendRequest e GetStatement separados por PONTO (nao por barra). E configuravel
# por Setting/ENV (IBKR_FLEX_BASE_URL) via Provider::IbkrAdapter.
class Provider::IbkrFlex
  class Error < StandardError; end

  # query_id/token ausentes ao instanciar o client.
  class ConfigurationError < Error; end

  # Token invalido/expirado/inativo, ou query_id que a IBKR nao valida. Acionavel:
  # o usuario precisa gerar/copiar de novo o par query_id + token no painel da IBKR.
  class AuthenticationError < Error; end

  # A Flex Query em si esta mal configurada (codigo 1014). Acionavel: revisar a
  # definicao da query no painel da IBKR.
  class InvalidQueryError < ConfigurationError; end

  # O extrato ainda estava sendo gerado depois de todas as tentativas de polling.
  # Acionavel: e transitorio -- basta sincronizar de novo em instantes.
  class StatementNotReadyError < Error; end

  class RateLimitError < Error; end

  class ApiError < Error
    attr_reader :error_code

    def initialize(message, error_code: nil)
      super(message)
      @error_code = error_code
    end
  end

  DEFAULT_BASE_URL = "https://gdcdyn.interactivebrokers.com".freeze
  SERVICE_PATH = "/Universal/servlet/FlexStatementService".freeze
  API_VERSION = 3

  # Codigos transitorios "extrato ainda sendo gerado / tente de novo em instantes".
  PENDING_ERROR_CODES = %w[1003 1004 1019].freeze
  # Credencial invalida (token/query nao validados pela IBKR).
  AUTH_ERROR_CODES = %w[1012 1015 1016 1017 1020].freeze
  # Flex Query mal definida.
  QUERY_ERROR_CODES = %w[1014].freeze
  # Excesso de requisicoes.
  RATE_LIMIT_ERROR_CODES = %w[1018].freeze

  DEFAULT_POLL_INTERVAL = 3
  DEFAULT_MAX_POLL_ATTEMPTS = 20

  attr_reader :query_id, :token, :base_url

  def initialize(query_id:, token:, base_url: nil, poll_interval: DEFAULT_POLL_INTERVAL, max_poll_attempts: DEFAULT_MAX_POLL_ATTEMPTS)
    raise ConfigurationError, "query_id e obrigatorio" if query_id.blank?
    raise ConfigurationError, "token e obrigatorio" if token.blank?

    @query_id = query_id.to_s.strip
    @token = token.to_s.strip
    @base_url = base_url.presence || DEFAULT_BASE_URL
    @poll_interval = poll_interval
    @max_poll_attempts = max_poll_attempts
  end

  # Baixa o XML bruto do extrato Flex (positions/trades/cash). Levanta os erros
  # tipados acima em caso de credencial invalida, query invalida, rate limit ou
  # extrato nao pronto.
  def download_statement
    reference_code = request_reference_code
    poll_statement(reference_code)
  end

  private

    attr_reader :poll_interval, :max_poll_attempts

    def request_reference_code
      xml = parse_xml(get("#{SERVICE_PATH}.SendRequest").body)
      raise_on_error!(xml)

      reference_code = xml.at_xpath("//ReferenceCode")&.text.to_s.strip
      raise ApiError.new("A IBKR nao devolveu um ReferenceCode.") if reference_code.blank?

      reference_code
    end

    def poll_statement(reference_code)
      attempts = 0

      loop do
        attempts += 1
        body = get("#{SERVICE_PATH}.GetStatement", q: reference_code).body
        xml = parse_xml(body)

        # Sucesso: o proprio documento do extrato (FlexQueryResponse).
        return body if xml.at_xpath("//FlexQueryResponse")

        error = build_error(xml)

        if error.is_a?(StatementNotReadyError)
          raise error if attempts >= max_poll_attempts

          sleep(poll_interval) if poll_interval.to_f.positive?
          next
        end

        raise(error || ApiError.new("A IBKR devolveu uma resposta inesperada."))
      end
    end

    # GET no FlexStatementService. `q` default = query_id (SendRequest); no
    # GetStatement passamos o ReferenceCode.
    def get(path, q: query_id)
      client.get(path) do |req|
        req.params["t"] = token
        req.params["q"] = q
        req.params["v"] = API_VERSION
      end
    rescue Faraday::Error => e
      raise ApiError.new("Falha de rede ao falar com a IBKR: #{e.message}")
    end

    def client
      @client ||= Faraday.new(url: base_url) do |faraday|
        faraday.options.timeout = 120
        faraday.headers["User-Agent"] = "Muquirana IBKR Flex Client"
        faraday.request(:retry, { max: 2, interval: 0.2, interval_randomness: 0.5, backoff_factor: 2 })
      end
    end

    def parse_xml(body)
      Nokogiri::XML(body.to_s)
    end

    # Levanta se a resposta de controle (FlexStatementResponse) indicar erro.
    def raise_on_error!(xml)
      error = build_error(xml)
      raise error if error
    end

    # Mapeia o par Status/ErrorCode do FlexStatementResponse para um erro tipado,
    # ou nil quando nao ha erro.
    def build_error(xml)
      status = xml.at_xpath("//Status")&.text.to_s.strip
      error_code = xml.at_xpath("//ErrorCode")&.text.to_s.strip.presence
      error_message = xml.at_xpath("//ErrorMessage")&.text.to_s.strip.presence

      return nil if error_code.blank? && status != "Fail"

      message = error_message || "A requisicao ao Flex da IBKR falhou"

      case error_code
      when *PENDING_ERROR_CODES
        StatementNotReadyError.new(message)
      when *AUTH_ERROR_CODES
        AuthenticationError.new(message)
      when *QUERY_ERROR_CODES
        InvalidQueryError.new(message)
      when *RATE_LIMIT_ERROR_CODES
        RateLimitError.new(message)
      else
        ApiError.new(message, error_code: error_code)
      end
    end
end
