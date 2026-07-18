# Client de baixo nivel da OpenAPI do CoinStats (https://openapiv1.coinstats.app).
# Autenticacao por X-API-KEY do proprio usuario. Serve o fluxo de carteira
# on-chain por ENDERECO PUBLICO (MetaMask/DeFi) -- nao ha OAuth nem custodia.
#
# Nao confundir com `Provider::CoinstatsAdapter` (o adapter da fundacao de contas)
# nem com a classe base `Provider`. Aqui e so o HTTP client.
#
# Baseado no Provider::Coinstats do Sure (we-promise/sure, AGPLv3), reescrito
# sobre Faraday (o Muquirana nao usa HTTParty) e com foco no cenario BR: os dois
# erros que mais aparecem no plano gratuito do CoinStats -- HTTP 406 (creditos
# esgotados) e HTTP 429 (rate-limit) -- viram ERROS TIPADOS que a camada de sync
# traduz em mensagem acionavel em pt-BR.
#
# Inclui Provider::RateLimitable para espacar as requisicoes (o plano gratuito e
# sensivel a rajada) e faz retry com backoff no 429.
class Provider::Coinstats
  include Provider::RateLimitable

  class Error < StandardError
    attr_reader :details

    def initialize(message, details: nil)
      super(message)
      @details = details
    end
  end

  # Chave invalida/ausente (HTTP 401/403).
  class AuthenticationError < Error; end

  # HTTP 406: creditos do plano esgotados. Acionavel: o usuario precisa aguardar a
  # renovacao do plano ou fazer upgrade no painel do CoinStats.
  class CreditsExhaustedError < Error; end

  # HTTP 429: rate-limit. Carrega o retry_after (header) para o backoff.
  class RateLimitError < Error
    attr_reader :retry_after

    def initialize(message, details: nil, retry_after: nil)
      super(message, details: details)
      @retry_after = retry_after
    end
  end

  class ApiError < Error; end

  BASE_URL = "https://openapiv1.coinstats.app".freeze
  PROVIDER_ENV_PREFIX = "COINSTATS".freeze
  MIN_REQUEST_INTERVAL = 0.5
  MAX_RETRIES = 2
  INITIAL_RETRY_DELAY = 1
  MAX_RETRY_DELAY = 10

  attr_reader :api_key, :base_url

  def initialize(api_key:, base_url: nil)
    @api_key = api_key
    @base_url = base_url.presence || BASE_URL
  end

  # Lista de blockchains suportadas, formatada para dropdown: [[label, value], ...]
  # Degrada para [] em erro (logado) -- a UI cai numa lista estatica de fallback.
  # https://coinstats.app/api-docs/openapi/get-blockchains
  def blockchain_options
    raw = get("/wallet/blockchains")
    items = raw.is_a?(Array) ? raw : Array(raw.is_a?(Hash) ? raw["data"] : nil)

    items.filter_map do |b|
      next unless b.is_a?(Hash)

      value = b["connectionId"] || b["id"] || b["name"]
      next if value.blank?

      label = b["name"].presence || value.to_s
      [ label, value.to_s ]
    end.uniq { |_label, value| value }.sort_by { |label, _| label.to_s.downcase }
  rescue Provider::Coinstats::Error => e
    Rails.logger.warn("Provider::Coinstats: falha ao listar blockchains: #{e.class} - #{e.message}")
    []
  end

  # Saldos de cripto de uma ou mais carteiras numa unica chamada.
  # @param wallets [String] lista "blockchain:address" separada por virgula
  #   (ex.: "ethereum:0x123abc,bitcoin:bc1qxyz")
  # @return [Array<Hash>] uma entrada por carteira: { blockchain, address, connectionId, balances: [...] }
  # https://coinstats.app/api-docs/openapi/get-wallet-balances
  def get_wallet_balances(wallets)
    return [] if wallets.blank?

    data = get("/wallet/balances", wallets: wallets)
    data.is_a?(Array) ? data : Array(data)
  end

  # Extrai os tokens de UMA carteira do retorno em lote de get_wallet_balances.
  def extract_wallet_balance(bulk_data, address, blockchain)
    return [] unless bulk_data.is_a?(Array)

    wallet = bulk_data.find do |entry|
      next false unless entry.is_a?(Hash)

      entry["address"]&.downcase == address&.downcase &&
        (entry["connectionId"]&.downcase == blockchain&.downcase ||
         entry["blockchain"]&.downcase == blockchain&.downcase)
    end

    return [] unless wallet

    Array(wallet["balances"])
  end

  # Posicoes DeFi (staking, LP, yield) de uma carteira.
  # @return [Hash] { "protocols" => [...] }
  # https://coinstats.app/api-docs/openapi/get-wallet-defi
  def get_wallet_defi(address:, connection_id:)
    data = get("/wallet/defi", address: address, connectionId: connection_id)
    data.is_a?(Hash) ? data : {}
  end

  private
    def get(path, **query)
      with_retries("GET #{path}") do
        response = client.get(path) do |req|
          query.each { |k, v| req.params[k.to_s] = v }
        end
        handle_response(response)
      end
    rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
      Rails.logger.error("Provider::Coinstats: #{path} falhou: #{e.class}: #{e.message}")
      raise Error.new("Falha ao contatar a API do CoinStats: #{e.message}")
    end

    # Throttle + retry com backoff no rate-limit (429). Demais erros propagam.
    def with_retries(operation_name, max_retries: MAX_RETRIES)
      retries = 0

      begin
        throttle_request
        yield
      rescue RateLimitError => e
        retries += 1
        raise if retries > max_retries

        delay = e.retry_after.presence || calculate_retry_delay(retries)
        Rails.logger.warn(
          "Provider::Coinstats: #{operation_name} com rate-limit " \
          "(tentativa #{retries}/#{max_retries}). Repetindo em #{delay}s..."
        )
        sleep(delay) if delay.to_f.positive?
        retry
      end
    end

    def calculate_retry_delay(retry_count)
      base_delay = INITIAL_RETRY_DELAY * (2**(retry_count - 1))
      jitter = base_delay * rand * 0.25
      [ base_delay + jitter, MAX_RETRY_DELAY ].min
    end

    def client
      @client ||= Faraday.new(url: base_url) do |faraday|
        faraday.headers["X-API-KEY"] = api_key
        faraday.headers["Accept"] = "application/json"
        faraday.headers["User-Agent"] = "Muquirana CoinStats Client"
        faraday.options.timeout = 60
      end
    end

    # https://coinstats.app/api-docs/errors -- codigos HTTP padrao.
    def handle_response(response)
      case response.status
      when 200..299
        parse_body(response.body)
      when 401
        raise_api_error(response, AuthenticationError, "Chave da API do CoinStats invalida ou ausente")
      when 403
        raise_api_error(response, AuthenticationError, "Acesso negado pelo CoinStats")
      when 406
        raise_api_error(response, CreditsExhaustedError, "Creditos do CoinStats esgotados")
      when 429
        raise_api_error(response, RateLimitError, "Limite de requisicoes do CoinStats excedido")
      else
        raise_api_error(response, ApiError, "Erro da API CoinStats (HTTP #{response.status})")
      end
    end

    def raise_api_error(response, error_class, fallback)
      payload = parse_error_payload(response&.body)
      message = payload[:message].presence || fallback
      message = "#{message} (requestId: #{payload[:request_id]})" if payload[:request_id].present?

      Rails.logger.error("Provider::Coinstats: HTTP #{response&.status} - #{fallback} - #{payload.inspect}")

      if error_class == RateLimitError
        raise error_class.new(message, details: payload.compact.presence, retry_after: retry_after_seconds(response))
      end

      raise error_class.new(message, details: payload.compact.presence)
    end

    def parse_error_payload(body)
      parsed = parse_body(body)
      return {} unless parsed.is_a?(Hash)

      {
        status_code: parsed["statusCode"] || parsed["status_code"],
        message: parsed["message"],
        request_id: parsed["requestId"] || parsed["request_id"],
        path: parsed["path"]
      }
    end

    def parse_body(body)
      return body if body.is_a?(Hash) || body.is_a?(Array)
      return nil if body.blank?

      JSON.parse(body)
    rescue JSON::ParserError
      nil
    end

    def retry_after_seconds(response)
      raw = response&.headers&.[]("Retry-After") || response&.headers&.[]("retry-after")
      return nil if raw.blank?

      Integer(raw)
    rescue ArgumentError, TypeError
      nil
    end
end
