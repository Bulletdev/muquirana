# Classe base para todos os adapters de provider de CONTA (AccountProvider).
#
# Nao confundir com a classe `Provider` (client de APIs externas: Provider::Plaid,
# Provider::OpenAI, ...). Aqui `Provider::Base` e a base dos adapters que ligam um
# registro especifico de provider (ex.: PlaidAccount) a uma Account do dominio.
#
# Para criar um novo adapter:
# 1. Herde de Provider::Base
# 2. Implemente #provider_name
# 3. Inclua modulos opcionais (Provider::Syncable)
# 4. Registre com Provider::Factory no corpo da classe
#
# Exemplo:
#   class Provider::AcmeAdapter < Provider::Base
#     Provider::Factory.register("AcmeAccount", self)
#     include Provider::Syncable
#
#     def provider_name = "acme"
#   end
class Provider::Base
  attr_reader :provider_account, :account

  def initialize(provider_account, account: nil)
    @provider_account = provider_account
    @account = account || provider_account.account
  end

  # Identificacao do provider - deve ser implementada pelas subclasses
  # @return [String] O nome do provider (ex.: "plaid")
  def provider_name
    raise NotImplementedError, "#{self.class} must implement #provider_name"
  end

  # Tipos de conta suportados por este provider
  # @return [Array<String>] (ex.: ["Depository", "CreditCard"])
  def self.supported_account_types
    []
  end

  # Configuracoes de conexao para a UI. Override nas subclasses.
  # @return [Array<Hash>]
  def self.connection_configs(family:)
    []
  end

  # Tipo do provider (nome da classe do registro de provider)
  # @return [String]
  def provider_type
    provider_account.class.name
  end

  # Se este provider permite deletar holdings
  # @return [Boolean]
  def can_delete_holdings?
    false
  end

  # Payload cru do provider
  def raw_payload
    provider_account.raw_payload if provider_account.respond_to?(:raw_payload)
  end

  # Metadados sobre este provider/conta
  # @return [Hash]
  def metadata
    base_metadata = {
      provider_name: provider_name,
      provider_type: provider_type
    }

    base_metadata.merge!(institution: institution_metadata) if respond_to?(:institution_metadata)
    base_metadata
  end
end
