class UI::Account::BalanceReconciliation < ApplicationComponent
  attr_reader :balance, :account

  def initialize(balance:, account:)
    @balance = balance
    @account = account
  end

  def reconciliation_items
    case account.accountable_type
    when "Depository", "OtherAsset", "OtherLiability"
      default_items
    when "CreditCard"
      credit_card_items
    when "Investment"
      investment_items
    when "Loan"
      loan_items
    when "Property", "Vehicle"
      asset_items
    when "Crypto"
      crypto_items
    else
      default_items
    end
  end

  private

    # Rotulo e tooltip vinham escritos em ingles aqui dentro, em ~60 literais.
    #
    # As chaves sao por VARIANTE mesmo quando o rotulo se repete: "Start
    # balance" existe em quase todas, mas o tooltip muda ("o saldo da conta"
    # para conta corrente, "o valor devido" para cartao). Chave compartilhada
    # obrigaria uma so explicacao para contextos diferentes.
    #
    # A duplicacao no YAML e proposital: e mais barata do que fallback esperto,
    # e deixa cada texto ajustavel sem efeito colateral nos outros.
    def item(variante, chave, value:, style:)
      escopo = "components.account.balance_reconciliation.#{variante}.#{chave}"

      {
        label: I18n.t("#{escopo}.label"),
        value: value,
        tooltip: I18n.t("#{escopo}.tooltip"),
        style: style
      }
    end

    def default_items
      items = [
        item(:default, :start_balance, value: balance.start_balance_money, style: :start),
        item(:default, :net_cash_flow, value: net_cash_flow, style: :flow)
      ]

      if has_adjustments?
        items << item(:default, :end_balance, value: end_balance_before_adjustments, style: :subtotal)
        items << item(:default, :adjustments, value: total_adjustments, style: :adjustment)
      end

      items << item(:default, :final_balance, value: balance.end_balance_money, style: :final)
      items
    end

    def credit_card_items
      items = [
        item(:credit_card, :start_balance, value: balance.start_balance_money, style: :start),
        item(:credit_card, :charges, value: balance.cash_outflows_money, style: :flow),
        item(:credit_card, :payments, value: balance.cash_inflows_money * -1, style: :flow)
      ]

      if has_adjustments?
        items << item(:credit_card, :end_balance, value: end_balance_before_adjustments, style: :subtotal)
        items << item(:credit_card, :adjustments, value: total_adjustments, style: :adjustment)
      end

      items << item(:credit_card, :final_balance, value: balance.end_balance_money, style: :final)
      items
    end

    def investment_items
      items = [
        item(:investment, :start_balance, value: balance.start_balance_money, style: :start)
      ]

      # Change in brokerage cash (includes deposits, withdrawals, and cash from trades)
      items << item(:investment, :brokerage_cash_change, value: net_cash_flow, style: :flow)

      # Change in holdings from trading activity
      items << item(:investment, :holdings_change_trades, value: net_non_cash_flow, style: :flow)

      # Market price changes
      items << item(:investment, :holdings_change_market, value: balance.net_market_flows_money, style: :flow)

      if has_adjustments?
        items << item(:investment, :end_balance, value: end_balance_before_adjustments, style: :subtotal)
        items << item(:investment, :adjustments, value: total_adjustments, style: :adjustment)
      end

      items << item(:investment, :final_balance, value: balance.end_balance_money, style: :final)
      items
    end

    def loan_items
      items = [
        item(:loan, :start_principal, value: balance.start_balance_money, style: :start),
        item(:loan, :net_principal_change, value: net_non_cash_flow, style: :flow)
      ]

      if has_adjustments?
        items << item(:loan, :end_principal, value: end_balance_before_adjustments, style: :subtotal)
        items << item(:loan, :adjustments, value: balance.non_cash_adjustments_money, style: :adjustment)
      end

      items << item(:loan, :final_principal, value: balance.end_balance_money, style: :final)
      items
    end

    def asset_items # Property/Vehicle
      items = [
        item(:asset, :start_value, value: balance.start_balance_money, style: :start),
        item(:asset, :net_value_change, value: net_total_flow, style: :flow)
      ]

      if has_adjustments?
        items << item(:asset, :end_value, value: end_balance_before_adjustments, style: :subtotal)
        items << item(:asset, :adjustments, value: total_adjustments, style: :adjustment)
      end

      items << item(:asset, :final_value, value: balance.end_balance_money, style: :final)
      items
    end

    def crypto_items
      items = [
        item(:crypto, :start_balance, value: balance.start_balance_money, style: :start)
      ]

      items << item(:crypto, :buys, value: balance.cash_outflows_money * -1, style: :flow) if balance.cash_outflows != 0
      items << item(:crypto, :sells, value: balance.cash_inflows_money, style: :flow) if balance.cash_inflows != 0
      items << item(:crypto, :market_changes, value: balance.net_market_flows_money, style: :flow) if balance.net_market_flows != 0

      if has_adjustments?
        items << item(:crypto, :end_balance, value: end_balance_before_adjustments, style: :subtotal)
        items << item(:crypto, :adjustments, value: total_adjustments, style: :adjustment)
      end

      items << item(:crypto, :final_balance, value: balance.end_balance_money, style: :final)
      items
    end

    def net_cash_flow
      balance.cash_inflows_money - balance.cash_outflows_money
    end

    def net_non_cash_flow
      balance.non_cash_inflows_money - balance.non_cash_outflows_money
    end

    def net_total_flow
      net_cash_flow + net_non_cash_flow + balance.net_market_flows_money
    end

    def total_adjustments
      balance.cash_adjustments_money + balance.non_cash_adjustments_money
    end

    def has_adjustments?
      balance.cash_adjustments != 0 || balance.non_cash_adjustments != 0
    end

    def end_balance_before_adjustments
      balance.end_balance_money - total_adjustments
    end
end
