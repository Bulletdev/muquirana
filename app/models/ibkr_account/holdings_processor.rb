# Materializa as posicoes abertas (OpenPositions) da IBKR em Holdings do dominio,
# convertendo preco e valor da moeda da posicao para a MOEDA DA FAMILIA (BRL).
#
# Portado do IbkrAccount::HoldingsProcessor do Sure (we-promise/sure, AGPLv3),
# adaptado ao modelo Holding do Muquirana (account.holdings, currency unica).
# Retorna o valor total das posicoes na moeda da familia.
class IbkrAccount::HoldingsProcessor
  include IbkrAccount::DataHelpers

  def initialize(ibkr_account, account:)
    @ibkr_account = ibkr_account
    @account = account
  end

  # @return [BigDecimal] valor total das holdings na moeda da familia
  def process
    total = BigDecimal("0")

    grouped_positions.each do |(_conid, _currency, report_date), rows|
      amount = process_group(rows, report_date)
      total += amount if amount
    end

    total
  end

  private
    attr_reader :ibkr_account, :account

    def family_currency
      account.currency
    end

    def grouped_positions
      Array(ibkr_account.raw_holdings_payload).each_with_object({}) do |position, groups|
        data = position.with_indifferent_access
        next unless supported_position?(data)

        currency = extract_currency(data, fallback: ibkr_account.currency)
        report_date = parse_date(data[:report_date]) || ibkr_account.report_date || Date.current
        key = [ data[:conid], currency, report_date ]
        groups[key] ||= []
        groups[key] << data
      end
    end

    # @return [BigDecimal, nil] valor da holding na moeda da familia
    def process_group(rows, report_date)
      sample = rows.first
      security = resolve_security(sample)
      return nil unless security

      native_price = parse_decimal(sample[:mark_price])
      aggregate = valid_lots(rows)
      return nil unless native_price && aggregate

      quantity = aggregate[:quantity]
      currency = extract_currency(sample, fallback: ibkr_account.currency)

      price_fam, _stale = convert_amount(native_price, from: currency, to: family_currency, date: report_date)
      price_fam = price_fam.round(4)
      amount_fam = (quantity * price_fam).round(4)

      holding = account.holdings.find_or_initialize_by(
        security: security,
        date: report_date,
        currency: family_currency
      )
      holding.assign_attributes(qty: quantity, price: price_fam, amount: amount_fam)
      holding.save!

      amount_fam
    end

    # Agrega apenas os lotes com position parseavel. Quando ha cost_basis_price,
    # calcula o custo medio ponderado; caso contrario a holding fica so com qty.
    def valid_lots(rows)
      total_quantity = BigDecimal("0")

      rows.each do |row|
        row_quantity = parse_decimal(row[:position])
        next unless row_quantity

        total_quantity += row_quantity.abs
      end

      return nil if total_quantity.zero?

      { quantity: total_quantity }
    end

    def supported_position?(row)
      row[:asset_category].to_s == "STK" &&
        row[:side].to_s.casecmp("Long").zero? &&
        row[:symbol].present? &&
        row[:currency].present? &&
        row[:position].present? &&
        row[:mark_price].present? &&
        row[:report_date].present?
    end
end
