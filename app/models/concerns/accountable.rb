module Accountable
  extend ActiveSupport::Concern

  TYPES = %w[Depository Investment Crypto Property Vehicle OtherAsset CreditCard Loan OtherLiability]

  # Define empty hash to ensure all accountables have this defined
  SUBTYPES = {}.freeze

  def self.from_type(type)
    return nil unless TYPES.include?(type)
    type.constantize
  end

  included do
    include Enrichable

    has_one :account, as: :accountable, touch: true
  end

  class_methods do
    def classification
      raise NotImplementedError, "Accountable must implement #classification"
    end

    def icon
      raise NotImplementedError, "Accountable must implement #icon"
    end

    def color
      raise NotImplementedError, "Accountable must implement #color"
    end

    # Given a subtype, look up the label for this accountable type
    #
    # As chaves de SUBTYPES ("checking", "401k") sao persistidas em
    # accounts.subtype -- nao sao traduziveis. So o rotulo exibido passa pelo
    # I18n, e o `default:` e o proprio rotulo em ingles do hash: um subtipo sem
    # chave de traducao continua exibindo exatamente o que o upstream exibia,
    # em vez de quebrar ou mostrar "translation missing".
    def subtype_label_for(subtype, format: :short)
      return nil if subtype.nil?

      label_type = format == :long ? :long : :short
      fallback = self::SUBTYPES[subtype]&.fetch(label_type, nil)
      return nil if fallback.nil?

      I18n.t(
        "accountables.#{self.name.underscore}.subtypes.#{subtype}.#{label_type}",
        default: fallback
      )
    end

    # Convenience method for getting the short label
    def short_subtype_label_for(subtype)
      subtype_label_for(subtype, format: :short)
    end

    # Convenience method for getting the long label
    def long_subtype_label_for(subtype)
      subtype_label_for(subtype, format: :long)
    end

    def favorable_direction
      classification == "asset" ? "up" : "down"
    end

    # Nome do tipo de conta exibido na UI (plural), ex: "Investimentos".
    #
    # O `default:` preserva o comportamento do upstream (`Investment` ->
    # "Investments") para qualquer accountable novo que ainda nao tenha chave.
    def display_name
      I18n.t("accountables.#{self.name.underscore}.display_name", default: self.name.pluralize.titleize)
    end

    # Versao no singular, ex: "Investimento".
    #
    # Nao derive esta forma com `display_name.singularize`: o singularize usa as
    # regras de inflexao do ingles e destroi palavras portuguesas ("Imoveis" ->
    # "Imovei"). Por isso a forma singular e uma chave propria.
    def display_name_singular
      I18n.t("accountables.#{self.name.underscore}.display_name_singular", default: self.name.titleize)
    end

    def balance_money(family)
      family.accounts
            .active
            .joins(sanitize_sql_array([
              "LEFT JOIN exchange_rates ON exchange_rates.date = :current_date AND accounts.currency = exchange_rates.from_currency AND exchange_rates.to_currency = :family_currency",
              { current_date: Date.current.to_s, family_currency: family.currency }
            ]))
            .where(accountable_type: self.name)
            .sum("accounts.balance * COALESCE(exchange_rates.rate, 1)")
    end
  end

  def display_name
    self.class.display_name
  end

  def display_name_singular
    self.class.display_name_singular
  end

  # Nao chamados em lugar nenhum (nem aqui nem no override de Property) --
  # codigo morto herdado do upstream. Nao internacionalizados de proposito:
  # criaria chave de locale orfa. Remover, ou usar, e decisao a parte.
  def balance_display_name
    "account value"
  end

  def opening_balance_display_name
    "opening balance"
  end

  def icon
    self.class.icon
  end

  def color
    self.class.color
  end

  def classification
    self.class.classification
  end
end
