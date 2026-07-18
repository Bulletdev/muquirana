# Busca as carteiras (accounts) da Coinbase e materializa um unico CoinbaseAccount
# "combined" com a lista de ativos de CRIPTO. A conversao para BRL e a criacao
# dos Holdings acontecem depois, no CoinbaseAccount::Processor/HoldingsProcessor.
#
# A Coinbase entrega, por carteira, tanto a quantidade de cripto (balance.amount)
# quanto o valor equivalente na MOEDA NATIVA da conta (native_balance.amount, em
# USD/EUR/etc.). Guardamos ambos: a moeda nativa e a base da conversao para BRL
# via Frankfurter/Money. Carteiras fiduciarias (type != "crypto") e carteiras
# zeradas ficam fora -- o escopo aqui e holding de cripto.
class CoinbaseItem::Importer
  attr_reader :coinbase_item, :coinbase_provider

  def initialize(coinbase_item, coinbase_provider:)
    @coinbase_item = coinbase_item
    @coinbase_provider = coinbase_provider
  end

  def import
    raise Provider::Coinbase::AuthenticationError, "Credenciais da Coinbase nao configuradas" unless coinbase_provider

    accounts_data = Array(coinbase_provider.get_accounts)

    assets = parse_assets(accounts_data)
    native_currency = detect_native_currency(assets)

    coinbase_account = upsert_coinbase_account(
      assets: assets,
      native_currency: native_currency,
      accounts_raw: accounts_data
    )

    coinbase_item.upsert_coinbase_snapshot!(
      "accounts" => accounts_data,
      "imported_at" => Time.current.iso8601
    )

    {
      success: true,
      assets_imported: assets.size,
      native_currency: native_currency,
      coinbase_account_id: coinbase_account.id
    }
  end

  private
    # Converte a lista de carteiras da Coinbase em ativos de cripto normalizados.
    def parse_assets(accounts_data)
      accounts_data.filter_map do |account_data|
        next unless account_data.is_a?(Hash)

        symbol = crypto_symbol(account_data)
        next if symbol.blank?

        # So cripto vira holding. Coinbase marca fiduciaria com currency.type "fiat".
        crypto_type = account_data.dig("currency", "type")
        next if crypto_type.present? && crypto_type != "crypto"

        quantity = account_data.dig("balance", "amount").to_d
        next if quantity.zero?

        {
          symbol: symbol,
          quantity: quantity.to_s("F"),
          native_amount: account_data.dig("native_balance", "amount"),
          native_currency: account_data.dig("native_balance", "currency"),
          crypto_name: account_data.dig("currency", "name") || symbol,
          account_id: account_data["id"]
        }.stringify_keys
      end
    end

    def crypto_symbol(account_data)
      (account_data.dig("balance", "currency") || account_data.dig("currency", "code")).to_s.upcase.presence
    end

    # Moeda fiduciaria nativa da conta Coinbase (USD/EUR/...). Coinbase usa a mesma
    # para todas as carteiras; pegamos a primeira disponivel, com fallback USD.
    def detect_native_currency(assets)
      assets.map { |a| a["native_currency"] }.compact.first.presence || "USD"
    end

    def upsert_coinbase_account(assets:, native_currency:, accounts_raw:)
      coinbase_account = coinbase_item.coinbase_accounts.find_or_initialize_by(account_type: "combined")

      # current_balance guarda o total na moeda NATIVA (soma dos native_balance);
      # o saldo final em BRL e computado no processor a partir dos holdings.
      total_native = assets.sum { |a| a["native_amount"].to_d }

      coinbase_account.assign_attributes(
        name: coinbase_item.institution_display_name,
        currency: native_currency,
        current_balance: total_native,
        institution_metadata: {
          "name" => coinbase_item.institution_name,
          "domain" => coinbase_item.institution_domain,
          "url" => coinbase_item.institution_url,
          "color" => coinbase_item.institution_color
        },
        raw_payload: {
          "assets" => assets,
          "native_currency" => native_currency,
          "accounts" => accounts_raw,
          "fetched_at" => Time.current.iso8601
        }
      )

      coinbase_account.save!
      coinbase_account
    end
end
