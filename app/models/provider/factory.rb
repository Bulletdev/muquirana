# Registro/descoberta dos adapters de provider de conta (AccountProvider).
# Mapeia um provider_type (nome da classe do registro, ex.: "PlaidAccount") para
# o adapter correspondente (Provider::PlaidAdapter).
class Provider::Factory
  class AdapterNotFoundError < StandardError; end

  class << self
    # Registra um adapter de provider
    def register(provider_type, adapter_class)
      registry[provider_type] = adapter_class
    end

    # Cria um adapter para um dado registro de provider
    # @param provider_account [PlaidAccount] o registro especifico do provider
    # @param account [Account] referencia opcional a conta
    # @return [Provider::Base]
    def create_adapter(provider_account, account: nil)
      return nil if provider_account.nil?

      provider_type = provider_account.class.name
      adapter_class = find_adapter_class(provider_type)

      raise AdapterNotFoundError, "No adapter registered for provider type: #{provider_type}" unless adapter_class

      adapter_class.new(provider_account, account: account)
    end

    # Cria um adapter a partir de um registro AccountProvider
    def from_account_provider(account_provider)
      return nil if account_provider.nil?

      create_adapter(account_provider.provider, account: account_provider.account)
    end

    # Lista dos provider_types registrados
    def registered_provider_types
      ensure_adapters_loaded
      registry.keys.sort
    end

    # Garante que todos os adapters foram carregados/registrados via autoload
    def ensure_adapters_loaded
      adapter_files.each do |adapter_name|
        adapter_class_name = "Provider::#{adapter_name}"

        begin
          adapter_class_name.constantize
        rescue NameError => e
          Rails.logger.warn("Failed to load adapter: #{adapter_class_name} - #{e.message}")
        end
      end
    end

    def registered?(provider_type)
      find_adapter_class(provider_type).present?
    end

    def registered_adapters
      ensure_adapters_loaded
      registry.values.uniq
    end

    def adapters_for_account_type(account_type)
      registered_adapters.select do |adapter_class|
        adapter_class.supported_account_types.include?(account_type)
      end
    end

    def supports_account_type?(account_type)
      adapters_for_account_type(account_type).any?
    end

    def connection_configs_for_account_type(account_type:, family:)
      adapters_for_account_type(account_type).flat_map do |adapter_class|
        adapter_class.connection_configs(family: family)
      end
    end

    # Limpa o registro (util em testes)
    def clear_registry!
      @registry = {}
    end

    private

      def registry
        @registry ||= {}
      end

      def find_adapter_class(provider_type)
        return registry[provider_type] if registry[provider_type]

        ensure_adapters_loaded
        registry[provider_type]
      end

      # Descobre os arquivos de adapter em app/models/provider/*_adapter.rb
      def adapter_files
        return [] unless defined?(Rails)

        pattern = Rails.root.join("app/models/provider/*_adapter.rb")
        Dir[pattern].map do |file|
          File.basename(file, ".rb").camelize
        end
      end
  end
end
