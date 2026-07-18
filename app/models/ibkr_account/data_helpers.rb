# Helpers de parsing compartilhados entre o ReportParser e os processors da IBKR.
# Portados do IbkrAccount::DataHelpers do Sure (we-promise/sure, AGPLv3).
module IbkrAccount::DataHelpers
  extend ActiveSupport::Concern

  private

    def parse_decimal(value)
      return nil if value.nil?

      normalized = value.is_a?(String) ? value.delete(",").strip : value.to_s
      return nil if normalized.blank? || normalized == "-"

      # Notacao contabil com parenteses: "(1234.56)" -> "-1234.56"
      normalized = "-#{normalized[1..-2]}" if normalized.start_with?("(") && normalized.end_with?(")")

      BigDecimal(normalized)
    rescue ArgumentError
      nil
    end

    def parse_date(value)
      return nil if value.blank?

      case value
      when Date
        value
      when Time, DateTime, ActiveSupport::TimeWithZone
        value.to_date
      else
        # A IBKR usa "YYYYMMDD" (sem separador) alem de formatos com ";".
        normalized = value.to_s.tr(";", " ").strip
        if normalized.match?(/\A\d{8}\z/)
          Date.parse(normalized) rescue nil
        else
          (Time.zone.parse(normalized)&.to_date rescue nil) || (Date.parse(normalized) rescue nil)
        end
      end
    rescue ArgumentError, TypeError
      nil
    end

    def parse_currency(value)
      value.present? ? value.to_s.strip.upcase : nil
    end

    def extract_currency(row, fallback: nil)
      value = row.with_indifferent_access[:currency]
      value.present? ? value.to_s.upcase : fallback
    end

    # Converte um valor da moeda `from` para a moeda `to` na `date`, usando
    # ExchangeRate.find_or_fetch_rate (Frankfurter). Retorna [valor, stale?]:
    # sem taxa, degrada mantendo o valor cru e marcando stale (nao quebra o sync).
    def convert_amount(amount, from:, to:, date:)
      return [ BigDecimal("0"), false ] if amount.nil?

      amount = amount.to_d
      from = from.to_s.upcase
      to = to.to_s.upcase
      return [ amount, false ] if from == to || from.blank?

      rate = ExchangeRate.find_or_fetch_rate(from: from, to: to, date: date, cache: true)
      if rate&.rate
        [ (amount * rate.rate.to_d), false ]
      else
        Rails.logger.warn("IbkrAccount - sem taxa #{from}->#{to} em #{date}; mantendo valor cru")
        [ amount, true ]
      end
    end

    # Resolve (ou cria) a Security do ticker. Usa Security::Resolver, que sem um
    # provider de securities (Synth) configurado degrada para uma security offline
    # -- sem tocar a rede.
    def resolve_security(row)
      data = row.with_indifferent_access
      ticker = data[:symbol].to_s.strip.upcase
      return nil if ticker.blank?

      Security::Resolver.new(ticker).resolve
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
      Security.find_by(ticker: ticker)
    end
end
