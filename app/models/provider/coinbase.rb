# Client de baixo nivel da API da Coinbase (CDP - Coinbase Developer Platform).
# Autenticacao por API-KEY do proprio usuario: um par (name, private key EC) da
# Coinbase, sem OAuth. Cada request e assinado com um JWT ES256 (ECDSA P-256)
# no padrao CDP.
#
# Nao confundir com `Provider::CoinbaseAdapter` (o adapter da fundacao de contas)
# nem com a classe base `Provider`. Aqui e so o HTTP client.
#
# Baseado no Provider::Coinbase do Sure (we-promise/sure, AGPLv3), reescrito
# sobre Faraday (o Muquirana nao usa HTTParty). A geracao do JWT (ES256, DER->raw
# r||s, parse do PEM EC com normalizacao de `\n`) foi copiada exatamente do
# padrao CDP -- e o unico jeito de a Coinbase aceitar a assinatura.
#
# ENDPOINTS confirmados vivos (2026-07, via curl):
#   GET https://api.coinbase.com/v2/accounts            (autenticado) -> 401 sem auth
#   GET https://api.coinbase.com/v2/prices/BTC-USD/spot (publico)     -> 200
#   GET https://api.coinbase.com/v2/prices/BTC-BRL/spot (publico)     -> 200
# A API v2 continua servindo saldos de carteira; nao foi deprecada como a TAPI v3
# do Mercado Bitcoin. A Advanced Trade (api.coinbase.com/api/v3) cobre trading,
# mas /v2/accounts segue sendo a rota de leitura de carteiras.
class Provider::Coinbase
  class Error < StandardError; end

  # Chave/assinatura invalida, ou a chave CDP nao tem permissao de leitura.
  class AuthenticationError < Error; end

  # A chave e valida mas foi barrada por falta de permissao/escopo (HTTP 403).
  # Acionavel: o usuario precisa habilitar a permissao "view" da chave no painel.
  class PermissionError < AuthenticationError; end

  class RateLimitError < Error; end
  class ApiError < Error; end

  DEFAULT_API_BASE_URL = "https://api.coinbase.com".freeze

  # Host usado dentro do claim `uri` do JWT. E o host canonico exigido pela CDP,
  # independente do base_url (que pode apontar para um proxy/mock em teste).
  JWT_HOST = "api.coinbase.com".freeze

  attr_reader :api_key, :api_secret, :api_base_url

  def initialize(api_key:, api_secret:, api_base_url: nil)
    @api_key = api_key
    @api_secret = api_secret
    @api_base_url = api_base_url.presence || DEFAULT_API_BASE_URL
  end

  # Dados do usuario da conta. Request autenticado. Retorna o hash "data".
  def get_user
    signed_get("/v2/user")["data"]
  end

  # Todas as carteiras (accounts). Segue a paginacao da Coinbase. Retorna um array
  # de hashes de carteira.
  def get_accounts
    paginated_get("/v2/accounts")
  end

  # Preco spot de um par (endpoint PUBLICO, sem auth), ex.: "BTC-USD" ou "BTC-BRL".
  # Retorna o hash "data" ({ "amount", "base", "currency" }) ou nil.
  def get_spot_price(currency_pair)
    response = client.get("/v2/prices/#{currency_pair}/spot") do |req|
      req.options.timeout = 10
    end
    handle_response(response)["data"]
  rescue Provider::Coinbase::Error => e
    Rails.logger.warn("Provider::Coinbase: falha ao buscar preco spot de #{currency_pair}: #{e.message}")
    nil
  end

  private

    def signed_get(path)
      response = client.get(path) do |req|
        auth_headers("GET", path).each { |k, v| req.headers[k] = v }
      end
      handle_response(response)
    end

    # Segue a paginacao "pagination.next_uri" da API v2 da Coinbase, agregando o
    # array "data" de cada pagina. Cada pagina e um request assinado -- o JWT
    # cobre o path SEM query string (exigencia do claim `uri` da CDP).
    def paginated_get(path)
      results = []
      current_path = path

      loop do
        response = client.get(current_path) do |req|
          auth_headers("GET", current_path.split("?").first).each { |k, v| req.headers[k] = v }
        end

        data = handle_response(response)
        results.concat(Array(data["data"]))

        next_uri = data.dig("pagination", "next_uri")
        break if next_uri.blank?

        uri = URI.parse(next_uri)
        current_path = uri.path
        current_path += "?#{uri.query}" if uri.query.present?
      end

      results
    end

    def client
      @client ||= Faraday.new(url: api_base_url) do |faraday|
        faraday.options.timeout = 30
        faraday.request(:retry, { max: 2, interval: 0.05, interval_randomness: 0.5, backoff_factor: 2 })
      end
    end

    # Parseia um PEM EC private key, normalizando sequencias literais `\n` para
    # quebras de linha reais. Chaves CDP da Coinbase costumam ser coladas como
    # uma unica linha com `\n` escapado (ex.: copiado direto do JSON de download).
    # Ambos os formatos sao aceitos.
    def parse_ec_private_key(pem)
      OpenSSL::PKey::EC.new(pem.to_s.gsub('\n', "\n"))
    end

    # Gera o JWT de autenticacao da CDP. Usa ES256 (ECDSA P-256) -- casa com o
    # formato de chave que a Coinbase CDP emite. api_secret deve ser um PEM EC
    # private key (-----BEGIN EC PRIVATE KEY-----), com `\n` reais ou literais.
    def generate_jwt(method, path)
      private_key = parse_ec_private_key(api_secret)

      now = Time.now.to_i
      uri = "#{method} #{JWT_HOST}#{path}"

      header = {
        alg: "ES256",
        kid: api_key,
        nonce: SecureRandom.hex(16),
        typ: "JWT"
      }

      payload = {
        sub: api_key,
        iss: "cdp",
        nbf: now,
        exp: now + 120,
        uri: uri
      }

      encoded_header = Base64.urlsafe_encode64(header.to_json, padding: false)
      encoded_payload = Base64.urlsafe_encode64(payload.to_json, padding: false)

      message = "#{encoded_header}.#{encoded_payload}"
      der_sig = private_key.sign(OpenSSL::Digest::SHA256.new, message)

      # Converte a assinatura DER para raw r||s (exigido pela spec do JWT).
      asn1 = OpenSSL::ASN1.decode(der_sig)
      r = asn1.value[0].value.to_s(2).rjust(32, "\x00")[-32..]
      s = asn1.value[1].value.to_s(2).rjust(32, "\x00")[-32..]
      encoded_signature = Base64.urlsafe_encode64(r + s, padding: false)

      "#{message}.#{encoded_signature}"
    rescue OpenSSL::PKey::ECError, OpenSSL::PKey::PKeyError => e
      # PEM invalido/mal colado: e um problema de credencial, nao de rede.
      raise AuthenticationError, "Segredo da API (chave privada) invalido: #{e.message}"
    end

    def auth_headers(method, path)
      {
        "Authorization" => "Bearer #{generate_jwt(method, path)}",
        "Content-Type" => "application/json"
      }
    end

    def handle_response(response)
      parsed = parse_body(response.body)

      case response.status
      when 200..299
        parsed.is_a?(Hash) ? parsed : { "data" => parsed }
      when 401
        raise AuthenticationError, extract_error_message(parsed) ||
          "Nao autorizado - confira a chave e o segredo da API"
      when 403
        raise PermissionError, extract_error_message(parsed) ||
          "Chave sem permissao para esta acao. Habilite a permissao de leitura no painel da Coinbase."
      when 429
        raise RateLimitError, "Limite de requisicoes da Coinbase excedido"
      else
        raise ApiError, extract_error_message(parsed) || "Erro da API Coinbase (HTTP #{response.status})"
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
      return parsed if parsed.is_a?(String) && parsed.present?
      return nil unless parsed.is_a?(Hash)

      parsed.dig("errors", 0, "message") || parsed["error_description"] || parsed["error"] || parsed["message"]
    end
end
