# Adapter do Plaid para a fundacao generica de providers.
#
# Com ele o Plaid vira "so mais um provider": envolve qualquer PlaidAccount
# (US ou EU) e delega o acesso a API ao Provider::Registry ja existente do
# Muquirana. O client de API continua sendo Provider::Plaid -- este adapter e
# apenas a ponte entre AccountProvider e o dominio.
class Provider::PlaidAdapter < Provider::Base
  include Provider::Syncable

  # Registra este adapter para TODA instancia de PlaidAccount
  Provider::Factory.register("PlaidAccount", self)

  def self.supported_account_types
    %w[Depository CreditCard Loan Investment]
  end

  def provider_name
    "plaid"
  end

  # --- Provider::Syncable ------------------------------------------------------
  def item
    provider_account.plaid_item
  end

  def sync_path
    Rails.application.routes.url_helpers.sync_plaid_item_path(item)
  end

  def can_delete_holdings?
    false
  end

  # --- Metadados de instituicao ------------------------------------------------
  def institution_metadata
    {
      name: institution_name,
      domain: institution_domain,
      url: institution_url,
      color: institution_color
    }
  end

  def institution_name
    item&.name
  end

  def institution_url
    item&.institution_url
  end

  def institution_color
    item&.institution_color
  end

  def institution_domain
    url_string = item&.institution_url
    return nil unless url_string.present?

    begin
      uri = URI.parse(url_string)
      uri.host&.gsub(/^www\./, "")
    rescue URI::InvalidURIError
      Rails.logger.warn("Invalid institution URL for Plaid account #{provider_account.id}: #{url_string}")
      nil
    end
  end
end
