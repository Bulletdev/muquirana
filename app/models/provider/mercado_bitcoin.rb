# Client de baixo nivel da API v4 do Mercado Bitcoin -- exchange 100% brasileira.
# A TAPI v3 (legada, TAPI-ID/TAPI-MAC + nonce) foi desligada: bater nela hoje
# retorna 404 "API|ROUTE_NOT_FOUND". A v4 usa OAuth-like: um POST em
# /api/v4/authorize troca login (id da chave) + password (segredo) por um
# access_token Bearer, que autentica as leituras de conta.
#
# Nao confundir com `Provider::MercadoBitcoinAdapter` (o adapter da fundacao de
# contas) nem com a classe base `Provider`. Aqui e so o HTTP client.
#
# O Mercado Bitcoin opera em BRL nativamente e nao ha restricao geografica (ja e
# uma exchange brasileira): rejeicao aqui vem de chave invalida ou falta de
# permissao, que viram ERROS TIPADOS traduzidos pela camada de sync em mensagem
# acionavel em pt-BR.
class Provider::MercadoBitcoin
  class Error < StandardError; end

  # Chave/segredo invalidos, ou key sem permissao de leitura de conta.
  class AuthenticationError < Error; end

  # A key e valida mas foi barrada por falta de permissao/escopo. Acionavel: o
  # usuario precisa habilitar as permissoes da chave no painel do Mercado Bitcoin.
  class PermissionError < AuthenticationError; end

  class RateLimitError < Error; end
  class ApiError < Error; end
  class InvalidSymbolError < ApiError; end

  DEFAULT_BASE_URL = "https://api.mercadobitcoin.net".freeze

  # Prefixo da API publica/privada v4.
  API_PATH = "/api/v4".freeze

  attr_reader :api_key, :api_secret, :base_url

  def initialize(api_key:, api_secret:, base_url: nil)
    @api_key = api_key
    @api_secret = api_secret
    @base_url = base_url.presence || DEFAULT_BASE_URL
  end

  # Saldos da conta. Mantem o formato historico esperado pelo importer:
  # { "balance" => { "brl" => {"available","total"}, "btc" => {...}, ... } }.
  # Requer autenticacao (authorize -> accounts -> balances).
  def get_account_info
    balances = authenticated_get("#{API_PATH}/accounts/#{primary_account_id}/balances")

    balance = {}
    Array(balances).each do |entry|
      next unless entry.is_a?(Hash)

      symbol = entry["symbol"].to_s.downcase
      next if symbol.blank?

      balance[symbol] = {
        "available" => entry["available"],
        "total" => entry["total"] || entry["available"]
      }
    end

    { "balance" => balance }
  end

  # Preco atual (last) de um par em BRL, ex.: "BTC" -> ticker BTC-BRL. Endpoint
  # publico de dados. Retorna string ou nil.
  def get_ticker_price(coin)
    data = public_get("#{API_PATH}/tickers", symbols: "#{coin.to_s.upcase}-BRL")
    ticker = data.is_a?(Array) ? data.first : nil
    ticker.is_a?(Hash) ? ticker["last"] : nil
  rescue Provider::MercadoBitcoin::Error => e
    Rails.logger.warn("Provider::MercadoBitcoin: falha ao buscar preco de #{coin}: #{e.message}")
    nil
  end

  private

    # A v4 exige o id da conta antes dos saldos. Usa a primeira conta retornada (o
    # Mercado Bitcoin entrega uma conta principal por usuario).
    def primary_account_id
      @primary_account_id ||= begin
        accounts = authenticated_get("#{API_PATH}/accounts")
        account = Array(accounts).find { |a| a.is_a?(Hash) && a["id"].present? }
        raise ApiError, "Mercado Bitcoin nao retornou nenhuma conta para esta chave" unless account

        account["id"]
      end
    end

    # Troca login/password por um access_token Bearer. Erros aqui sao de credencial:
    # viram AuthenticationError com mensagem acionavel.
    def access_token
      @access_token ||= begin
        response = client.post("#{API_PATH}/authorize") do |req|
          req.headers["Content-Type"] = "application/json"
          req.body = JSON.generate(login: api_key.to_s, password: api_secret.to_s)
        end

        parsed = parse_body(response.body)

        unless response.status.between?(200, 299)
          raise RateLimitError, "Limite de requisicoes do Mercado Bitcoin excedido" if response.status == 429

          msg = extract_error_message(parsed)
          raise AuthenticationError, msg ||
            "Credenciais do Mercado Bitcoin recusadas (HTTP #{response.status}). Confira a chave, o segredo e as permissoes no painel."
        end

        token = parsed.is_a?(Hash) ? parsed["access_token"] : nil
        raise AuthenticationError, "Mercado Bitcoin nao retornou token de acesso" if token.blank?

        token
      end
    end

    def authenticated_get(path, **query)
      response = client.get(path) do |req|
        req.headers["Authorization"] = "Bearer #{access_token}"
        query.each { |k, v| req.params[k.to_s] = v }
      end
      handle_response(response)
    end

    def public_get(path, **query)
      response = client.get(path) do |req|
        query.each { |k, v| req.params[k.to_s] = v }
      end
      handle_response(response)
    end

    def client
      @client ||= Faraday.new(url: base_url) do |faraday|
        faraday.options.timeout = 30
        faraday.request(:retry, { max: 2, interval: 0.05, interval_randomness: 0.5, backoff_factor: 2 })
      end
    end

    def handle_response(response)
      parsed = parse_body(response.body)

      case response.status
      when 200..299
        parsed
      when 401
        raise AuthenticationError, extract_error_message(parsed) ||
          "Chave ou segredo invalidos, ou sem permissao de leitura de conta"
      when 403
        raise PermissionError, extract_error_message(parsed) ||
          "Chave sem permissao para ler a conta. Habilite a permissao no painel do Mercado Bitcoin."
      when 429
        raise RateLimitError, "Limite de requisicoes do Mercado Bitcoin excedido"
      else
        raise ApiError, extract_error_message(parsed) ||
          "Erro da API Mercado Bitcoin (HTTP #{response.status})"
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

      parsed["message"] || parsed["error_message"] || parsed["msg"] || parsed["error"]
    end
end
