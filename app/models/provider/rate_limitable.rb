# Concern compartilhado para providers que precisam de throttling por intervalo
# entre requisicoes e um padrao unico de transformacao de erro.
#
# Portado do Sure (we-promise/sure, AGPLv3). Providers que incluem este concern
# ganham:
# - `throttle_request`: dorme para garantir MIN_REQUEST_INTERVAL entre chamadas
# - `min_request_interval`: le de ENV com fallback para a constante da classe
# - `default_error_transformer`: mapeia erros Faraday/rate-limit para tipos do provider
#
# A classe que inclui DEVE definir:
# - `MIN_REQUEST_INTERVAL` (Float) -- segundos padrao entre requisicoes
# - `Error` (Class)               -- classe de erro do provider
# - `RateLimitError` (Class)      -- classe de rate-limit do provider
#
# E PODE definir uma constante `PROVIDER_ENV_PREFIX` (ex.: "COINSTATS") usada para
# derivar a chave de ENV do intervalo minimo. Sem ela, o prefixo vem do nome da
# classe (Provider::Coinstats -> "COINSTATS").
module Provider::RateLimitable
  extend ActiveSupport::Concern

  private
    # Garante um intervalo minimo entre requisicoes consecutivas nesta instancia.
    def throttle_request
      @last_request_time ||= Time.at(0)
      elapsed = Time.current - @last_request_time
      sleep_time = min_request_interval - elapsed
      sleep(sleep_time) if sleep_time > 0
      @last_request_time = Time.current
    end

    def min_request_interval
      ENV.fetch("#{provider_env_prefix}_MIN_REQUEST_INTERVAL", self.class::MIN_REQUEST_INTERVAL).to_f
    end

    def provider_env_prefix
      if self.class.const_defined?(:PROVIDER_ENV_PREFIX)
        self.class::PROVIDER_ENV_PREFIX
      else
        self.class.name.demodulize.underscore.upcase
      end
    end

    # Transformacao padrao de erro: mapeia erros comuns de Faraday para as classes
    # de erro do provider. Providers com tipos extras devem sobrescrever e chamar
    # `super` para os casos default.
    def default_error_transformer(error)
      case error
      when self.class::RateLimitError
        error
      when Faraday::TooManyRequestsError
        self.class::RateLimitError.new(
          "#{self.class.name.demodulize} rate limit exceeded",
          details: error.response&.dig(:body)
        )
      when Faraday::Error
        self.class::Error.new(error.message, details: error.response&.dig(:body))
      else
        self.class::Error.new(error.message)
      end
    end
end
