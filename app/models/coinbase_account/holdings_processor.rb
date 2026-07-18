# Cria/atualiza os Holdings do dominio a partir dos ativos de cripto importados
# da Coinbase. Cada cripto vira UM Holding, resolvido por Security::Resolver com
# o padrao CRYPTO:<codigo>, valorizado na MOEDA DA FAMILIA (BRL).
#
# Conversao (coracao do escopo): a Coinbase entrega o valor de cada carteira na
# moeda nativa da conta (native_balance, em USD/EUR). Convertemos essa fiduciaria
# nativa -> BRL via ExchangeRate/Frankfurter (Money). Se a Coinbase nao trouxer o
# native_balance, buscamos o preco spot no par nativo (best-effort) e convertemos.
class CoinbaseAccount::HoldingsProcessor
  # Coinbase MIC para securities offline de cripto (mesmo criterio do Sure).
  EXCHANGE_MIC = "XCBS".freeze

  attr_reader :coinbase_account

  # @param account [Account, nil] a Account ja resolvida (evita depender da
  #   associacao memoizada de coinbase_account). Se nil, cai na associacao.
  def initialize(coinbase_account, account: nil)
    @coinbase_account = coinbase_account
    @account = account
  end

  def process
    return unless account&.accountable_type == "Crypto"

    coinbase_account.assets.each do |asset|
      process_asset(asset)
    rescue => e
      Rails.logger.error("CoinbaseAccount::HoldingsProcessor - erro no ativo #{asset.inspect}: #{e.class} - #{e.message}")
    end
  end

  private
    def account
      @account ||= coinbase_account.account
    end

    def family
      coinbase_account.coinbase_item.family
    end

    def target_currency
      @target_currency ||= family.currency
    end

    def native_currency
      coinbase_account.native_currency
    end

    def process_asset(asset)
      symbol = asset["symbol"].to_s.upcase
      quantity = asset["quantity"].to_d
      return if symbol.blank? || quantity.zero?

      security = resolve_security(symbol, asset["crypto_name"])
      return unless security

      amount = value_in_target_currency(asset, quantity, symbol)
      price = quantity.zero? ? 0 : (amount / quantity).round(4)

      holding = account.holdings.find_or_initialize_by(
        security: security,
        date: Date.current,
        currency: target_currency
      )
      holding.assign_attributes(qty: quantity, price: price, amount: amount)
      holding.save!

      # Remove holdings dessa security em datas futuras (higiene, como o Plaid).
      account.holdings.where(security: security).where("date > ?", Date.current).destroy_all

      holding
    end

    # Resolve a Security de cripto pelo padrao CRYPTO:<codigo>. O Resolver ja cai
    # para uma security offline quando nao ha match; ainda assim protegemos contra
    # falha de rede do provider de busca, criando a offline manualmente.
    def resolve_security(symbol, crypto_name)
      ticker = "CRYPTO:#{symbol}"
      Security::Resolver.new(ticker, exchange_operating_mic: EXCHANGE_MIC).resolve
    rescue => e
      Rails.logger.warn("CoinbaseAccount::HoldingsProcessor - Resolver falhou para #{ticker}: #{e.class} - #{e.message}; criando security offline")
      Security.find_or_initialize_by(ticker: ticker, exchange_operating_mic: EXCHANGE_MIC).tap do |sec|
        sec.name = crypto_name if sec.name.blank?
        sec.offline = true if sec.respond_to?(:offline=)
        sec.save!
      end
    end

    # Valor do ativo na moeda da familia (BRL). Fonte primaria: native_balance da
    # Coinbase (fiduciaria nativa), convertido via Frankfurter. Fallback: preco
    # spot no par nativo.
    def value_in_target_currency(asset, quantity, symbol)
      native_amount = asset["native_amount"].to_d
      native_amount = spot_native_value(symbol, quantity) if native_amount.zero?

      return 0.to_d if native_amount.zero?

      convert_to_target(native_amount)
    end

    # Converte um valor da moeda nativa (USD/EUR) para a moeda da familia (BRL)
    # via ExchangeRate/Frankfurter (Money). Sem taxa disponivel, degrada para 0.
    def convert_to_target(native_amount)
      from = native_currency.to_s.upcase
      return native_amount.round(4) if from == target_currency.to_s.upcase

      rate = ExchangeRate.find_or_fetch_rate(from: from, to: target_currency, date: Date.current, cache: true)
      unless rate&.rate
        Rails.logger.warn("CoinbaseAccount::HoldingsProcessor - sem taxa #{from}->#{target_currency}; holding fica com valor 0")
        return 0.to_d
      end

      (native_amount * rate.rate.to_d).round(4)
    end

    # Best-effort: valor na moeda nativa a partir do preco spot Coinbase do par
    # "SIMBOLO-NATIVA". So usado quando a Coinbase nao trouxe native_balance.
    def spot_native_value(symbol, quantity)
      provider = coinbase_account.coinbase_item.coinbase_provider
      return 0.to_d unless provider

      data = provider.get_spot_price("#{symbol}-#{native_currency}")
      price = data.is_a?(Hash) ? data["amount"].to_d : 0.to_d
      (quantity * price).round(8)
    rescue Provider::Coinbase::Error => e
      Rails.logger.warn("CoinbaseAccount::HoldingsProcessor - sem preco spot para #{symbol}: #{e.message}")
      0.to_d
    end
end
