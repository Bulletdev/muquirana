# Busca os saldos da carteira Spot e materializa um unico BinanceAccount
# "combined" com o valor total em USD (a conversao para a moeda da familia
# acontece depois, no BinanceAccount::Processor).
#
# Versao enxuta do Importer do Sure: so Spot. Margin/Earn/Futures/P2P e trade
# history ficaram fora do escopo deste cluster (prioridade = saldo em BRL).
class BinanceItem::Importer
  attr_reader :binance_item, :binance_provider

  def initialize(binance_item, binance_provider:)
    @binance_item = binance_item
    @binance_provider = binance_provider
  end

  def import
    raise Provider::Binance::AuthenticationError, "Credenciais da Binance nao configuradas" unless binance_provider

    raw = binance_provider.get_spot_account
    assets = parse_assets(raw.is_a?(Hash) ? raw["balances"] : nil)
    total_usd = calculate_total_usd(assets)

    binance_account = upsert_binance_account(assets: assets, total_usd: total_usd, spot_raw: raw)

    binance_item.upsert_binance_snapshot!(
      "spot" => raw,
      "imported_at" => Time.current.iso8601
    )

    { success: true, assets_imported: assets.size, total_usd: total_usd, binance_account_id: binance_account.id }
  end

  private
    def parse_assets(balances)
      Array(balances).filter_map do |b|
        free = b["free"].to_d
        locked = b["locked"].to_d
        total = free + locked
        next if total.zero?

        { symbol: b["asset"], free: free.to_s("F"), locked: locked.to_s("F"), total: total.to_s("F") }
      end
    end

    def calculate_total_usd(assets)
      assets.sum do |asset|
        quantity = asset[:total].to_d
        next 0 if quantity.zero?

        quantity * price_for(asset[:symbol])
      end.round(2)
    end

    def price_for(symbol)
      return 1.to_d if BinanceAccount::STABLECOINS.include?(symbol)

      binance_provider.get_spot_price("#{symbol}USDT").to_d
    rescue Provider::Binance::Error => e
      Rails.logger.warn("BinanceItem::Importer - sem preco para #{symbol}: #{e.message}")
      0.to_d
    end

    def upsert_binance_account(assets:, total_usd:, spot_raw:)
      binance_account = binance_item.binance_accounts.find_or_initialize_by(account_type: "combined")

      binance_account.assign_attributes(
        name: binance_item.institution_display_name,
        currency: "USD",
        current_balance: total_usd,
        institution_metadata: {
          "name" => binance_item.institution_name,
          "domain" => binance_item.institution_domain,
          "url" => binance_item.institution_url,
          "color" => binance_item.institution_color
        },
        raw_payload: {
          "spot" => spot_raw,
          "assets" => assets.map(&:stringify_keys),
          "fetched_at" => Time.current.iso8601
        }
      )

      binance_account.save!
      binance_account
    end
end
