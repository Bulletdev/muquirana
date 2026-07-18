# Materializa/atualiza a Account de INVESTIMENTO do dominio para um IbkrAccount:
# cria a Account e o vinculo AccountProvider (como o PlaidAccount::Processor),
# materializa Holdings e Trades e ancora o saldo atual.
#
# CORACAO DO ESCOPO: o portfolio da IBKR e multi-moeda (USD, GBP, ...). Tudo e
# convertido para a MOEDA DA FAMILIA (BRL) via ExchangeRate.find_or_fetch_rate
# (Frankfurter), o mesmo mecanismo usado pelo BinanceAccount::Processor.
class IbkrAccount::Processor
  include IbkrAccount::DataHelpers

  attr_reader :ibkr_account

  def initialize(ibkr_account)
    @ibkr_account = ibkr_account
  end

  def process
    return unless family

    IbkrAccount.transaction do
      account = ibkr_account.account || build_account

      account.assign_attributes(
        accountable: account.accountable || Investment.new,
        currency: family.currency,
        # balance/cash_balance sao NOT NULL; o valor real e ancorado depois de
        # materializar as holdings (set_current_balance mais abaixo).
        balance: account.balance || 0,
        cash_balance: account.cash_balance || 0
      )
      account.name = ibkr_account.name if account.name.blank?
      account.save!

      # Fundacao generica: garante o join polimorfico antes de materializar
      ibkr_account.ensure_account_provider!(account)
      account.reload

      holdings_value = IbkrAccount::HoldingsProcessor.new(ibkr_account, account: account).process
      IbkrAccount::ActivitiesProcessor.new(ibkr_account, account: account).process

      cash = cash_in_family_currency
      total = (holdings_value + cash).round(4)

      account.update!(cash_balance: cash)
      account.set_current_balance(total)

      account
    end
  end

  private
    def family
      ibkr_account.ibkr_item.family
    end

    def build_account
      family.accounts.build(
        name: ibkr_account.name,
        currency: family.currency,
        accountable: Investment.new
      )
    end

    # Caixa da conta (na moeda base da IBKR) convertido para a moeda da familia.
    def cash_in_family_currency
      raw_cash = (ibkr_account.cash_balance || 0).to_d
      converted, _stale = convert_amount(
        raw_cash,
        from: ibkr_account.currency,
        to: family.currency,
        date: ibkr_account.report_date || Date.current
      )
      converted.round(4)
    end
end
