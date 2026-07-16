# Provedor de cambio pela API do Frankfurter (https://frankfurter.dev): livre,
# sem chave, dados de bancos centrais (BCE e outros). Substitui o Synth para
# COTACAO DE MOEDA -- o Synth foi descontinuado junto com a Maybe
# (api.synthfinance.com nao resolve mais).
#
# Nao cobre preco de acao (o Synth cobria; o Frankfurter e so cambio). Uma conta
# em moeda que a API nao publica degrada como antes: sem saldo historico.
#
# A logica de porte veio do Provider::Frankfurter da comunidade Sure
# (github.com/we-promise/sure, AGPLv3), adaptada ao contrato de provider deste
# repositorio (with_provider_response, Rate, client).
#
# API v2 (api.frankfurter.dev/v2): a v2 carrega fim de semana e feriado do lado
# do servidor -- uma consulta de data em dia sem prega devolve a ultima cotacao
# conhecida direto, entao este provider nao precisa de logica de janela.
class Provider::Frankfurter < Provider
  include ExchangeRateConcept

  Error = Class.new(Provider::Error)

  # Sem chave: endpoint publico. FRANKFURTER_URL e a valvula de escape para quem
  # quiser rodar a propria instancia do Frankfurter (ele e self-hostable), do
  # mesmo jeito que SYNTH_URL era para o Synth.
  def initialize
  end

  # GET /v2/rate/{from}/{to}?date=... -> { date:, base:, quote:, rate: }
  # A data devolvida pode diferir da pedida (a v2 carrega o ultimo dia util),
  # mas nunca vem faltando.
  def fetch_exchange_rate(from:, to:, date:)
    from = sanitize_currency(from)
    to = sanitize_currency(to)

    with_provider_response do
      if from == to
        Rate.new(date: date.to_date, from: from, to: to, rate: 1.0)
      else
        response = client.get("/v2/rate/#{from}/#{to}") do |req|
          req.params["date"] = date.to_s
        end

        body = JSON.parse(response.body)
        raise Error, "Resposta inesperada do Frankfurter" unless body.is_a?(Hash) && body["rate"]

        Rate.new(date: Date.parse(body["date"].to_s), from: from, to: to, rate: body["rate"].to_f)
      end
    end
  end

  # GET /v2/rates?base=&quotes=&from=&to= -> [ { date:, quote:, rate: }, ... ]
  def fetch_exchange_rates(from:, to:, start_date:, end_date:)
    from = sanitize_currency(from)
    to = sanitize_currency(to)

    with_provider_response do
      if from == to
        (start_date.to_date..end_date.to_date).map do |d|
          Rate.new(date: d, from: from, to: to, rate: 1.0)
        end
      else
        response = client.get("/v2/rates") do |req|
          req.params["base"] = from
          req.params["quotes"] = to
          req.params["from"] = start_date.to_s
          req.params["to"] = end_date.to_s
        end

        body = JSON.parse(response.body)
        raise Error, "Resposta inesperada do Frankfurter (esperava lista)" unless body.is_a?(Array)

        body.filter_map do |entry|
          next unless entry.is_a?(Hash) && entry["quote"] == to && entry["rate"]

          Rate.new(date: Date.parse(entry["date"].to_s), from: from, to: to, rate: entry["rate"].to_f)
        end.sort_by(&:date)
      end
    end
  end

  private

    def base_url
      ENV["FRANKFURTER_URL"].presence || "https://api.frankfurter.dev"
    end

    def client
      @client ||= Faraday.new(url: base_url) do |faraday|
        faraday.request(:retry, { max: 2, interval: 0.05, interval_randomness: 0.5, backoff_factor: 2 })
        faraday.response :raise_error
      end
    end

    # from/to sao interpolados no PATH da URL (/rate/{from}/{to}); tira tudo que
    # nao for letra antes de usar. Codigo ISO 4217 e sempre A-Z de qualquer jeito.
    def sanitize_currency(code)
      code.to_s.upcase.gsub(/[^A-Z]/, "")
    end
end
