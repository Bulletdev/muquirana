# Materializa os trades (Trades) da IBKR em entries do tipo Trade no dominio,
# convertendo preco e valor da moeda do trade para a MOEDA DA FAMILIA (BRL).
#
# Portado do IbkrAccount::ActivitiesProcessor do Sure (we-promise/sure, AGPLv3),
# reduzido ao essencial do escopo (posicoes + trades) e adaptado ao modelo
# Entry/Trade do Muquirana. Escreve com external_id + source = "ibkr" (a chave da
# fundacao generica), idempotente entre syncs.
class IbkrAccount::ActivitiesProcessor
  include IbkrAccount::DataHelpers

  def initialize(ibkr_account, account:)
    @ibkr_account = ibkr_account
    @account = account
  end

  # @return [Integer] numero de trades materializados
  def process
    trades.count { |trade| process_trade(trade.with_indifferent_access) }
  end

  private
    attr_reader :ibkr_account, :account

    def trades
      Array((ibkr_account.raw_activities_payload || {}).with_indifferent_access[:trades])
    end

    def family_currency
      account.currency
    end

    def process_trade(row)
      return false unless supported_trade?(row)

      security = resolve_security(row)
      return false unless security

      quantity = parse_decimal(row[:quantity])
      native_price = parse_decimal(row[:trade_price])
      return false if quantity.nil? || native_price.nil?

      sell = row[:buy_sell].to_s.casecmp("SELL").zero?
      signed_quantity = sell ? -quantity.abs : quantity.abs
      currency = extract_currency(row, fallback: ibkr_account.currency)
      date = parse_date(row[:trade_date]) || Date.current

      price_fam, _stale = convert_amount(native_price, from: currency, to: family_currency, date: date)
      price_fam = price_fam.round(4)
      amount_fam = (signed_quantity * price_fam).round(4)

      entry = account.entries.find_or_initialize_by(external_id: "ibkr_trade_#{row[:trade_id]}", source: "ibkr") do |e|
        e.entryable = Trade.new
      end

      # Guarda contra colisao de tipo com outra entryable ja usando o mesmo id.
      return false if entry.persisted? && !entry.entryable.is_a?(Trade)

      entry.assign_attributes(
        amount: amount_fam,
        currency: family_currency,
        date: date,
        name: Trade.build_name(sell ? "sell" : "buy", signed_quantity, security.ticker)
      )
      entry.trade.assign_attributes(
        security: security,
        qty: signed_quantity,
        price: price_fam,
        currency: family_currency
      )
      entry.save!

      true
    rescue => e
      Rails.logger.error("IbkrAccount::ActivitiesProcessor - falha no trade #{row[:trade_id]}: #{e.message}")
      false
    end

    def supported_trade?(row)
      row[:asset_category].to_s == "STK" &&
        row[:buy_sell].present? &&
        row[:symbol].present? &&
        row[:currency].present? &&
        row[:quantity].present? &&
        row[:trade_date].present? &&
        row[:trade_id].present? &&
        row[:trade_price].present?
    end
end
