# Busca os saldos da conta no Mercado Bitcoin e materializa um unico
# MercadoBitcoinAccount "combined" com o valor total ja em BRL (a exchange opera
# em BRL nativamente; nao ha conversao de moeda como na Binance).
#
# O saldo em BRL entra direto (fator 1). Cripto e valorizada em BRL pelo ticker
# publico do proprio Mercado Bitcoin.
class MercadoBitcoinItem::Importer
  # Moeda fiduciaria nativa: entra no total sem conversao.
  FIAT_CURRENCY = "brl".freeze

  attr_reader :mercado_bitcoin_item, :mercado_bitcoin_provider

  def initialize(mercado_bitcoin_item, mercado_bitcoin_provider:)
    @mercado_bitcoin_item = mercado_bitcoin_item
    @mercado_bitcoin_provider = mercado_bitcoin_provider
  end

  def import
    unless mercado_bitcoin_provider
      raise Provider::MercadoBitcoin::AuthenticationError, "Credenciais do Mercado Bitcoin nao configuradas"
    end

    raw = mercado_bitcoin_provider.get_account_info
    assets = parse_assets(raw.is_a?(Hash) ? raw["balance"] : nil)
    total_brl = calculate_total_brl(assets)

    mb_account = upsert_mercado_bitcoin_account(assets: assets, total_brl: total_brl, account_raw: raw)

    mercado_bitcoin_item.upsert_mercado_bitcoin_snapshot!(
      "account" => raw,
      "imported_at" => Time.current.iso8601
    )

    { success: true, assets_imported: assets.size, total_brl: total_brl, mercado_bitcoin_account_id: mb_account.id }
  end

  private
    # O balance da TAPI e um hash { "brl" => {"available","total"}, "btc" => {...} }.
    def parse_assets(balance)
      return [] unless balance.is_a?(Hash)

      balance.filter_map do |symbol, amounts|
        available = amounts.is_a?(Hash) ? amounts["available"].to_d : amounts.to_d
        total = amounts.is_a?(Hash) ? (amounts["total"] || amounts["available"]).to_d : amounts.to_d
        next if total.zero?

        { symbol: symbol.to_s, available: available.to_s("F"), total: total.to_s("F") }
      end
    end

    def calculate_total_brl(assets)
      assets.sum do |asset|
        quantity = asset[:total].to_d
        next 0 if quantity.zero?

        quantity * price_for(asset[:symbol])
      end.round(2)
    end

    def price_for(symbol)
      return 1.to_d if symbol.to_s.downcase == FIAT_CURRENCY

      mercado_bitcoin_provider.get_ticker_price(symbol).to_d
    rescue Provider::MercadoBitcoin::Error => e
      Rails.logger.warn("MercadoBitcoinItem::Importer - sem preco para #{symbol}: #{e.message}")
      0.to_d
    end

    def upsert_mercado_bitcoin_account(assets:, total_brl:, account_raw:)
      mb_account = mercado_bitcoin_item.mercado_bitcoin_accounts.find_or_initialize_by(account_type: "combined")

      mb_account.assign_attributes(
        name: mercado_bitcoin_item.institution_display_name,
        currency: "BRL",
        current_balance: total_brl,
        institution_metadata: {
          "name" => mercado_bitcoin_item.institution_name,
          "domain" => mercado_bitcoin_item.institution_domain,
          "url" => mercado_bitcoin_item.institution_url,
          "color" => mercado_bitcoin_item.institution_color
        },
        raw_payload: {
          "account" => account_raw,
          "assets" => assets.map(&:stringify_keys),
          "fetched_at" => Time.current.iso8601
        }
      )

      mb_account.save!
      mb_account
    end
end
