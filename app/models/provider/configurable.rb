# Modulo para adapters de provider declararem seus requisitos de CONFIGURACAO
# (ex.: chaves de API globais, hosts alternativos), portado do Sure
# (we-promise/sure, AGPLv3) e adaptado ao Muquirana.
#
# Diferente de `Provider::Registry` (que descobre CLIENTS de API por conceito) e
# de `Provider::Factory` (que mapeia provider_type -> adapter de conta), este
# modulo cuida da configuracao declarativa de cada provider: cada campo e lido
# de Setting -> ENV -> default, sem exigir declaracao de `field` no modelo
# Setting. Nao colide com nenhum dos dois: o registro proprio vive em
# `Provider::ConfigurationRegistry`.
#
# Exemplo de uso num adapter:
#   class Provider::BinanceAdapter < Provider::Base
#     include Provider::Configurable
#
#     configure do
#       field :spot_base_url,
#             label: "URL base da API Spot",
#             env_key: "BINANCE_SPOT_BASE_URL",
#             default: "https://api.binance.com"
#     end
#   end
#
# O provider_key e derivado do nome da classe:
#   Provider::BinanceAdapter -> "binance"
#
# Campos ficam armazenados com chaves tipo "binance_spot_base_url".
# Acesse valores via: config_value(:spot_base_url) ou configuration.get_value(:spot_base_url)
module Provider::Configurable
  extend ActiveSupport::Concern

  class_methods do
    # Define a configuracao deste provider
    def configure(&block)
      @configuration = Configuration.new(provider_key)
      @configuration.instance_eval(&block)
      Provider::ConfigurationRegistry.register(provider_key, @configuration, self)
    end

    # Retorna a configuracao deste provider
    def configuration
      @configuration || Provider::ConfigurationRegistry.get(provider_key)
    end

    # Chave do provider derivada do nome da classe
    # Ex.: Provider::BinanceAdapter -> "binance"
    def provider_key
      name.demodulize.gsub(/Adapter$/, "").underscore
    end

    # Le um valor de configuracao
    def config_value(field_name)
      configuration&.get_value(field_name)
    end

    # Todos os campos obrigatorios presentes?
    def configured?
      configuration&.configured? || false
    end

    # Recarrega configuracao especifica do provider (override quando necessario).
    # Chamado apos as settings serem atualizadas na UI.
    def reload_configuration
      # Implementacao padrao nao faz nada
    end
  end

  # Metodos de instancia
  def provider_key
    self.class.provider_key
  end

  def configuration
    self.class.configuration
  end

  def config_value(field_name)
    self.class.config_value(field_name)
  end

  def configured?
    self.class.configured?
  end

  # DSL de configuracao
  class Configuration
    attr_reader :provider_key, :fields, :provider_description

    def initialize(provider_key)
      @provider_key = provider_key
      @fields = []
      @provider_description = nil
      @configured_check = nil
    end

    # Descricao do provider (markdown suportado na UI)
    def description(text)
      @provider_description = text
    end

    # Checagem customizada de "configurado?"
    def configured_check(&block)
      @configured_check = block
    end

    # Define um campo de configuracao
    def field(name, label:, required: false, secret: false, env_key: nil, default: nil, description: nil)
      @fields << ConfigField.new(
        name: name,
        label: label,
        required: required,
        secret: secret,
        env_key: env_key,
        default: default,
        description: description,
        provider_key: @provider_key
      )
    end

    # Valor de um campo (Setting -> ENV -> default)
    def get_value(field_name)
      field = fields.find { |f| f.name == field_name }
      return nil unless field

      field.value
    end

    # Provider esta configurado corretamente?
    def configured?
      if @configured_check
        instance_eval(&@configured_check)
      else
        required_fields = fields.select(&:required)
        if required_fields.any?
          required_fields.all? { |f| f.value.present? }
        else
          false
        end
      end
    end

    # Todos os valores como hash
    def to_h
      fields.each_with_object({}) do |field, hash|
        hash[field.name] = field.value
      end
    end
  end

  # Um unico campo de configuracao
  class ConfigField
    attr_reader :name, :label, :required, :secret, :env_key, :default, :description, :provider_key

    def initialize(name:, label:, required:, secret:, env_key:, default:, description:, provider_key:)
      @name = name
      @label = label
      @required = required
      @secret = secret
      @env_key = env_key
      @default = default
      @description = description
      @provider_key = provider_key
    end

    # Chave da Setting deste campo. Ex.: binance_spot_base_url
    def setting_key
      "#{provider_key}_#{name}".to_sym
    end

    # Valor do campo (Setting -> ENV -> default)
    def value
      # Adaptacao Muquirana: rails-settings-cached 2.x expoe as settings por
      # ACESSOR de metodo (Setting.chave), nao por bracket (Setting[:chave]).
      # So consultamos quando o campo foi declarado no modelo Setting.
      setting_value = Setting.respond_to?(setting_key) ? Setting.public_send(setting_key) : nil
      return normalize_value(setting_value) if setting_value.present?

      if env_key.present?
        env_value = ENV[env_key]
        return normalize_value(env_value) if env_value.present?
      end

      normalize_value(default)
    end

    def present?
      value.present?
    end

    def valid?
      validate.empty?
    end

    def validate
      errors = []
      current_value = value

      if required && current_value.blank?
        errors << "#{label} is required"
      end

      errors
    end

    def validate!
      errors = validate
      raise ArgumentError, "Invalid configuration for #{setting_key}: #{errors.join(", ")}" if errors.any?
      true
    end

    private
      def normalize_value(val)
        return nil if val.nil?
        normalized = val.to_s.strip
        normalized.empty? ? nil : normalized
      end
  end
end

# Registro de todas as configuracoes de provider. Nome DISTINTO de
# `Provider::Registry` (client de APIs) de proposito -- nao ha colisao.
module Provider::ConfigurationRegistry
  class << self
    def register(provider_key, configuration, adapter_class = nil)
      registry[provider_key] = configuration
      adapter_registry[provider_key] = adapter_class if adapter_class
    end

    def get(provider_key)
      registry[provider_key]
    end

    def all
      registry.values
    end

    def providers
      registry.keys
    end

    def get_adapter_class(provider_key)
      adapter_registry[provider_key]
    end

    # Util em testes
    def clear!
      @registry = {}
      @adapter_registry = {}
    end

    private
      def registry
        @registry ||= {}
      end

      def adapter_registry
        @adapter_registry ||= {}
      end
  end
end
