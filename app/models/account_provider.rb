# Join polimorfico entre uma Account e o registro especifico do provider que a
# alimenta (ex.: PlaidAccount). Substitui a FK 1:1 direta
# (accounts.plaid_account_id), permitindo que o Plaid seja "so mais um provider"
# e abrindo espaco para futuros providers sem hardcode.
class AccountProvider < ApplicationRecord
  belongs_to :account
  belongs_to :provider, polymorphic: true

  validates :account_id, uniqueness: { scope: :provider_type }
  validates :provider_id, uniqueness: { scope: :provider_type }

  # Retorna o adapter (Provider::Base) desta conexao
  def adapter
    Provider::Factory.create_adapter(provider, account: account)
  end

  # Nome do provider, delegado ao adapter (fallback = provider_type underscored)
  def provider_name
    adapter&.provider_name || provider_type.underscore
  end
end
