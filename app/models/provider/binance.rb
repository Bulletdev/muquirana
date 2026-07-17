# Client de baixo nivel da API da Binance (Spot). Autenticacao por API-KEY do
# proprio usuario (HMAC-SHA256), sem OAuth.
#
# Nao confundir com `Provider::BinanceAdapter` (o adapter da fundacao de contas)
# nem com a classe base `Provider`. Aqui e so o HTTP client.
#
# Baseado no Provider::Binance do Sure (we-promise/sure, AGPLv3), reescrito sobre
# Faraday (o Muquirana nao usa HTTParty) e com tratamento de erro voltado ao
# cenario BR: rejeicao por geografia/regulacao/permissao vira um ERRO TIPADO que
# a camada de sync traduz em mensagem acionavel em pt-BR.
class Provider::Binance
  class Error < StandardError; end

  # Chave/assinatura invalida, ou key sem a permissao "Enable Reading".
  class AuthenticationError < Error; end

  # A key e valida mas foi barrada por IP/permissao (Binance code -2015). Acionavel:
  # o usuario precisa habilitar leitura e/ou liberar o IP na propria Binance.
  class PermissionError < AuthenticationError; end

  # Barrado por geografia/regulacao (HTTP 451, ou mensagem de "restricted
  # location"). No BR isso acontece quando a key/host esta fora do escopo elegivel.
  class GeoRestrictedError < Error; end

  class RateLimitError < Error; end
  class ApiError < Error; end
  class InvalidSymbolError < ApiError; end

  DEFAULT_SPOT_BASE_URL = "https://api.binance.com".freeze

  attr_reader :api_key, :api_secret, :spot_base_url

  def initialize(api_key:, api_secret:, spot_base_url: nil)
    @api_key = api_key
    @api_secret = api_secret
    @spot_base_url = spot_base_url.presence || DEFAULT_SPOT_BASE_URL
  end

  # Carteira Spot -- requer request assinado. Retorna o hash com "balances".
  def get_spot_account
    signed_get("/api/v3/account")
  end

  # Preco spot de um par (endpoint publico), ex.: "BTCUSDT". Retorna string ou nil.
  def get_spot_price(symbol)
    data = public_get("/api/v3/ticker/price", symbol: symbol)
    data.is_a?(Hash) ? data["price"] : nil
  rescue Provider::Binance::Error => e
    Rails.logger.warn("Provider::Binance: falha ao buscar preco de #{symbol}: #{e.message}")
    nil
  end

  private

    def public_get(path, **query)
      response = client.get(path) do |req|
        query.each { |k, v| req.params[k.to_s] = v }
      end
      handle_response(response)
    end

    def signed_get(path, extra_params: {})
      params = timestamp_params.merge(extra_params)
      query_string = URI.encode_www_form(params.sort)
      signature = sign(query_string)

      response = client.get(path) do |req|
        req.headers["X-MBX-APIKEY"] = api_key
        # A assinatura precisa cobrir exatamente a query enviada; montamos a
        # string manualmente para nao depender da reordenacao do Faraday.
        req.options.params_encoder = Faraday::FlatParamsEncoder
        req.params = Faraday::Utils.parse_query("#{query_string}&signature=#{signature}")
      end

      handle_response(response)
    end

    def timestamp_params
      { "timestamp" => (Time.current.to_f * 1000).to_i.to_s, "recvWindow" => "5000" }
    end

    def sign(query_string)
      OpenSSL::HMAC.hexdigest("sha256", api_secret.to_s, query_string)
    end

    def client
      @client ||= Faraday.new(url: spot_base_url) do |faraday|
        faraday.options.timeout = 30
        faraday.request(:retry, { max: 2, interval: 0.05, interval_randomness: 0.5, backoff_factor: 2 })
      end
    end

    def handle_response(response)
      parsed = parse_body(response.body)

      case response.status
      when 200..299
        parsed
      when 418, 429
        raise RateLimitError, "Limite de requisicoes da Binance excedido"
      when 451
        raise GeoRestrictedError, extract_error_message(parsed) || "Servico indisponivel a partir de uma localidade restrita"
      else
        raise_mapped_error(response.status, parsed)
      end
    end

    # Mapeia os erros da Binance (HTTP + code interno) para as classes tipadas.
    def raise_mapped_error(status, parsed)
      code = parsed.is_a?(Hash) ? parsed["code"] : nil
      msg = extract_error_message(parsed)

      # Geografia/regulacao pode chegar como texto mesmo fora do 451.
      if msg.to_s.match?(/restricted location|Service unavailable from a restricted|eligibility/i)
        raise GeoRestrictedError, msg
      end

      case code
      when -2015
        # "Invalid API-key, IP, or permissions for action"
        raise PermissionError, msg || "Chave invalida, IP nao autorizado ou sem permissao"
      when -2014, -1022, -1125, -1099
        raise AuthenticationError, msg || "Falha de autenticacao"
      when -1121
        raise InvalidSymbolError, msg || "Par invalido"
      else
        if status == 401 || status == 403
          raise AuthenticationError, msg || "Nao autorizado (HTTP #{status})"
        end
        raise ApiError, msg || "Erro da API Binance (HTTP #{status})"
      end
    end

    def parse_body(body)
      return body if body.is_a?(Hash) || body.is_a?(Array)
      return nil if body.blank?

      JSON.parse(body)
    rescue JSON::ParserError
      body
    end

    def extract_error_message(parsed)
      return parsed if parsed.is_a?(String)
      return nil unless parsed.is_a?(Hash)

      parsed["msg"] || parsed["message"] || parsed["error"]
    end
end
