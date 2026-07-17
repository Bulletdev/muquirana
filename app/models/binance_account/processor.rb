# Materializa/atualiza a Account do dominio para um BinanceAccount e -- coracao
# do escopo -- converte o saldo (importado em USD) para a MOEDA DA FAMILIA (BRL),
# reusando ExchangeRate.find_or_fetch_rate (mesmo mecanismo do Sure).
#
# Cria a Account e o vinculo AccountProvider automaticamente (como o
# PlaidAccount::Processor faz), validando a fundacao generica ponta a ponta.
class BinanceAccount::Processor
  attr_reader :binance_account

  def initialize(binance_account)
    @binance_account = binance_account
  end

  def process
    BinanceAccount.transaction do
      account = binance_account.account || build_account

      raw_usd = (binance_account.current_balance || 0).to_d
      amount, stale, rate_date = convert_from_usd(raw_usd)

      account.assign_attributes(
        accountable: account.accountable || Crypto.new,
        balance: amount,
        cash_balance: 0,
        currency: family.currency
      )
      account.name = binance_account.name if account.name.blank?
      account.save!

      # Fundacao generica: garante o join polimorfico
      AccountProvider.find_or_create_by!(
        account: account,
        provider_type: "BinanceAccount",
        provider_id: binance_account.id
      )

      account.set_current_balance(amount)

      binance_account.update!(
        extra: binance_account.extra.to_h.deep_merge(build_stale_extra(stale, rate_date))
      )

      account
    end
  end

  private
    def family
      binance_account.binance_item.family
    end

    def build_account
      family.accounts.build(
        name: binance_account.name,
        currency: family.currency,
        accountable: Crypto.new
      )
    end

    # Converte um valor em USD para a moeda da familia.
    # @return [Array(BigDecimal, Boolean, Date|nil)] (valor, stale?, data_da_taxa)
    def convert_from_usd(amount_usd)
      target = family.currency

      return [ amount_usd, false, Date.current ] if target.to_s.upcase == "USD"

      rate = ExchangeRate.find_or_fetch_rate(from: "USD", to: target, date: Date.current, cache: true)

      if rate.present?
        [ (amount_usd * rate.rate.to_d).round(4), false, (rate.respond_to?(:date) ? rate.date : Date.current) ]
      else
        # Sem taxa: degrada mantendo o numero cru e marcando stale (nao quebra o item).
        Rails.logger.warn("BinanceAccount::Processor - sem taxa USD->#{target} para conta #{binance_account.id}")
        [ amount_usd, true, nil ]
      end
    end

    def build_stale_extra(stale, rate_date, as_of = Date.current)
      {
        "binance" => {
          "stale_rate" => stale,
          "rate_date" => rate_date&.to_s,
          "converted_at" => as_of.to_s
        }
      }
    end
end
