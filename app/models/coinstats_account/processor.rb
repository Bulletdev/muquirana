# Materializa/atualiza a Account do dominio para um CoinstatsAccount e -- coracao
# do escopo -- converte o saldo agregado (importado em USD) para a MOEDA DA
# FAMILIA (BRL), reusando ExchangeRate.find_or_fetch_rate (Money/Frankfurter).
#
# Mesmo padrao do BinanceAccount::Processor: cria a Account e o vinculo
# AccountProvider se ainda nao existir.
class CoinstatsAccount::Processor
  attr_reader :coinstats_account

  def initialize(coinstats_account)
    @coinstats_account = coinstats_account
  end

  def process
    CoinstatsAccount.transaction do
      account = coinstats_account.account || build_account

      raw_usd = (coinstats_account.current_balance || 0).to_d
      amount, stale, rate_date = convert_from_usd(raw_usd)

      account.assign_attributes(
        accountable: account.accountable || Crypto.new,
        balance: amount,
        cash_balance: 0,
        currency: family.currency
      )
      account.name = coinstats_account.name if account.name.blank?
      account.save!

      coinstats_account.ensure_account_provider!(account)

      account.set_current_balance(amount)

      coinstats_account.update!(
        extra: coinstats_account.extra.to_h.deep_merge(build_stale_extra(stale, rate_date))
      )

      account
    end
  end

  private
    def family
      coinstats_account.coinstats_item.family
    end

    def build_account
      family.accounts.build(
        name: coinstats_account.name,
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
        Rails.logger.warn("CoinstatsAccount::Processor - sem taxa USD->#{target} para conta #{coinstats_account.id}")
        [ amount_usd, true, nil ]
      end
    end

    def build_stale_extra(stale, rate_date, as_of = Date.current)
      {
        "coinstats" => {
          "stale_rate" => stale,
          "rate_date" => rate_date&.to_s,
          "converted_at" => as_of.to_s
        }
      }
    end
end
