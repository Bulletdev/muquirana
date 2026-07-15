class UI::Account::Chart < ApplicationComponent
  attr_reader :account

  def initialize(account:, period: nil, view: nil)
    @account = account
    @period = period
    @view = view
  end

  def period
    @period ||= Period.last_30_days
  end

  def holdings_value_money
    account.balance_money - account.cash_balance_money
  end

  def view_balance_money
    case view
    when "balance"
      account.balance_money
    when "holdings_balance"
      holdings_value_money
    when "cash_balance"
      account.cash_balance_money
    end
  end

  # O rotulo acima do saldo. Eram sete literais em ingles ("Balance",
  # "Debt balance"...) aparecendo na tela com a app em portugues.
  def title
    case account.accountable_type
    when "Investment", "Crypto"
      # `view` vem de parametro de URL; se vier lixo, view_balance_money ja
      # devolve nil. Aqui o mesmo: sem titulo inventado para view invalida.
      return nil unless %w[balance holdings_balance cash_balance].include?(view)

      I18n.t("components.account.chart.titles.investment.#{view}")
    when "Property", "Vehicle"
      # NAO usar accountable_type.humanize.downcase: isso e inflexao inglesa e
      # produz "property"/"vehicle" no meio de uma frase em portugues. O nome
      # traduzido do tipo vem do proprio accountable.
      I18n.t("components.account.chart.titles.asset",
             tipo: Accountable.from_type(account.accountable_type).display_name_singular.downcase)
    when "CreditCard", "OtherLiability"
      I18n.t("components.account.chart.titles.debt")
    when "Loan"
      I18n.t("components.account.chart.titles.loan")
    else
      I18n.t("components.account.chart.titles.default")
    end
  end

  def foreign_currency?
    account.currency != account.family.currency
  end

  def converted_balance_money
    return nil unless foreign_currency?

    account.balance_money.exchange_to(account.family.currency, fallback_rate: 1)
  end

  def view
    @view ||= "balance"
  end

  def series
    account.balance_series(period: period, view: view)
  end

  def trend
    series.trend
  end
end
