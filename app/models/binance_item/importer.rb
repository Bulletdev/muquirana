# Busca os saldos das carteiras da Binance e materializa um unico BinanceAccount
# "combined" com o valor total em USD (a conversao para a moeda da familia
# acontece depois, no BinanceAccount::Processor).
#
# Agrega Spot + Funding + Simple Earn (flexivel e locked) -- muita gente no BR
# deixa saldo fora da Spot (Funding para P2P, Earn para rendimento), e so Spot
# mostraria saldo zerado. Funding/Earn sao best-effort: se a key nao tiver a
# permissao ou o endpoint falhar, seguimos com o que ja temos. Margin/Futures e
# historico de trade continuam fora do escopo.
class BinanceItem::Importer
  attr_reader :binance_item, :binance_provider

  def initialize(binance_item, binance_provider:)
    @binance_item = binance_item
    @binance_provider = binance_provider
  end

  def import
    raise Provider::Binance::AuthenticationError, "Credenciais da Binance nao configuradas" unless binance_provider

    spot_raw = binance_provider.get_spot_account
    funding_raw = fetch_optional { binance_provider.get_funding_wallet }
    flexible_raw = fetch_optional { binance_provider.get_flexible_earn_positions }
    locked_raw = fetch_optional { binance_provider.get_locked_earn_positions }

    assets = aggregate_assets(spot_raw, funding_raw, flexible_raw, locked_raw)
    total_usd = calculate_total_usd(assets)

    raw = {
      "spot" => spot_raw,
      "funding" => funding_raw,
      "earn_flexible" => flexible_raw,
      "earn_locked" => locked_raw
    }

    binance_account = upsert_binance_account(assets: assets, total_usd: total_usd, raw: raw)

    binance_item.upsert_binance_snapshot!(raw.merge("imported_at" => Time.current.iso8601))

    { success: true, assets_imported: assets.size, total_usd: total_usd, binance_account_id: binance_account.id }
  end

  private
    # Best-effort: uma carteira sem permissao (ou endpoint fora do ar) nao pode
    # derrubar o sync inteiro; a Spot ja carrega o caso principal.
    def fetch_optional
      yield
    rescue Provider::Binance::Error => e
      Rails.logger.warn("BinanceItem::Importer - carteira adicional indisponivel: #{e.message}")
      nil
    end

    # Soma as quantidades de cada ativo entre Spot, Funding e Earn.
    def aggregate_assets(spot_raw, funding_raw, flexible_raw, locked_raw)
      totals = Hash.new(0.to_d)

      Array(spot_raw.is_a?(Hash) ? spot_raw["balances"] : nil).each do |b|
        add_quantity(totals, b["asset"], b["free"].to_d + b["locked"].to_d)
      end

      Array(funding_raw).each do |b|
        next unless b.is_a?(Hash)

        held = b["free"].to_d + b["locked"].to_d + b["freeze"].to_d + b["withdrawing"].to_d
        add_quantity(totals, b["asset"], held)
      end

      Array(flexible_raw.is_a?(Hash) ? flexible_raw["rows"] : nil).each do |r|
        add_quantity(totals, r["asset"], r["totalAmount"].to_d)
      end

      Array(locked_raw.is_a?(Hash) ? locked_raw["rows"] : nil).each do |r|
        add_quantity(totals, r["asset"], r["amount"].to_d)
      end

      totals.filter_map do |symbol, quantity|
        next if quantity.zero?

        { symbol: symbol, total: quantity.to_s("F") }
      end
    end

    def add_quantity(totals, asset, quantity)
      return if asset.blank? || quantity.nil? || quantity.zero?

      totals[asset] += quantity
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

    def upsert_binance_account(assets:, total_usd:, raw:)
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
        raw_payload: raw.merge(
          "assets" => assets.map(&:stringify_keys),
          "fetched_at" => Time.current.iso8601
        )
      )

      binance_account.save!
      binance_account
    end
end
