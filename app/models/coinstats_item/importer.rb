# Rebusca saldos + posicoes DeFi de cada carteira ja vinculada e atualiza o
# CoinstatsAccount correspondente com o total agregado em USD.
#
# Decisao de UX (ver WalletLinker/DefiAccountManager): UMA Account por carteira
# (endereco + chain). O saldo dessa conta e a soma do valor de todos os tokens
# on-chain + o valor de todas as posicoes DeFi, tudo em USD. A conversao para a
# moeda da familia (BRL) acontece depois, no CoinstatsAccount::Processor.
class CoinstatsItem::Importer
  attr_reader :coinstats_item, :coinstats_provider

  def initialize(coinstats_item, coinstats_provider:)
    @coinstats_item = coinstats_item
    @coinstats_provider = coinstats_provider
  end

  def import
    raise Provider::Coinstats::AuthenticationError, "Chave da API do CoinStats nao configurada" unless coinstats_provider

    results = coinstats_item.coinstats_accounts.map do |coinstats_account|
      refresh_wallet!(coinstats_account)
    end

    coinstats_item.upsert_coinstats_snapshot!(
      "wallets" => results.map { |r| r.except(:coinstats_account) },
      "imported_at" => Time.current.iso8601
    )

    { success: true, wallets_imported: results.size }
  end

  # Busca saldos on-chain + DeFi de uma carteira e devolve o snapshot agregado.
  # Reutilizado pelo WalletLinker no vinculo inicial.
  # @return [Hash] { total_usd:, tokens:, defi_positions: }
  def build_wallet_snapshot(address:, blockchain:)
    balances = coinstats_provider.get_wallet_balances("#{blockchain}:#{address}")
    tokens = coinstats_provider.extract_wallet_balance(balances, address, blockchain)
    tokens_total_usd = tokens.sum { |token| token_value_usd(token) }

    defi = fetch_optional_defi(address: address, blockchain: blockchain)

    {
      total_usd: (tokens_total_usd + defi.total_usd).round(2),
      tokens: normalize_tokens(tokens),
      defi_positions: defi.positions
    }
  end

  # Versao em lote de build_wallet_snapshot para o vinculo multi-chain (MetaMask
  # e outras EVM usam o MESMO endereco em varias chains). Faz UMA UNICA chamada de
  # saldos para todas as chains (o endpoint aceita "chain:addr,chain:addr,..."),
  # economizando credito do plano free. O DeFi custa credito POR chain, entao so e
  # buscado onde ha tokens -- o caso de DeFi sem nenhum token e raro; chains sem
  # token nem DeFi sao puladas pelo WalletBatchLinker.
  # @return [Hash{String=>Hash}] blockchain => { total_usd:, tokens:, defi_positions: }
  def build_wallet_snapshots(address:, blockchains:)
    chains = Array(blockchains).map { |b| b.to_s.strip.downcase }.reject(&:blank?).uniq
    return {} if chains.empty?

    wallets = chains.map { |chain| "#{chain}:#{address}" }.join(",")
    balances = coinstats_provider.get_wallet_balances(wallets)

    chains.index_with do |blockchain|
      tokens = coinstats_provider.extract_wallet_balance(balances, address, blockchain)
      tokens_total_usd = tokens.sum { |token| token_value_usd(token) }

      defi = if tokens.any?
        fetch_optional_defi(address: address, blockchain: blockchain)
      else
        CoinstatsItem::DefiAccountManager::Result.new(total_usd: 0.to_d, positions: [])
      end

      {
        total_usd: (tokens_total_usd + defi.total_usd).round(2),
        tokens: normalize_tokens(tokens),
        defi_positions: defi.positions
      }
    end
  end

  private
    def refresh_wallet!(coinstats_account)
      snapshot = build_wallet_snapshot(
        address: coinstats_account.wallet_address,
        blockchain: coinstats_account.blockchain
      )

      coinstats_account.update!(
        current_balance: snapshot[:total_usd],
        currency: "USD",
        raw_payload: {
          "address" => coinstats_account.wallet_address,
          "blockchain" => coinstats_account.blockchain,
          "tokens" => snapshot[:tokens],
          "defi_positions" => snapshot[:defi_positions],
          "total_usd" => snapshot[:total_usd].to_s,
          "fetched_at" => Time.current.iso8601
        }
      )

      { coinstats_account: coinstats_account, address: coinstats_account.wallet_address, blockchain: coinstats_account.blockchain, total_usd: snapshot[:total_usd].to_s, tokens: snapshot[:tokens].size, defi_positions: snapshot[:defi_positions].size }
    end

    # DeFi e best-effort: uma carteira sem DeFi (ou um endpoint instavel) nao pode
    # derrubar o sync do saldo on-chain. MAS creditos esgotados (406) e rate-limit
    # (429) PROPAGAM -- sao acionaveis e o usuario precisa saber.
    def fetch_optional_defi(address:, blockchain:)
      CoinstatsItem::DefiAccountManager
        .new(coinstats_item, provider: coinstats_provider)
        .wallet_defi_value(address: address, blockchain: blockchain)
    rescue Provider::Coinstats::CreditsExhaustedError, Provider::Coinstats::RateLimitError
      raise
    rescue Provider::Coinstats::Error => e
      Rails.logger.warn("CoinstatsItem::Importer - DeFi indisponivel para #{blockchain}:#{address}: #{e.message}")
      CoinstatsItem::DefiAccountManager::Result.new(total_usd: 0.to_d, positions: [])
    end

    # Valor em USD de um token = quantidade * preco. price pode ser escalar ou
    # Hash { "USD" => ... }.
    def token_value_usd(token)
      token = token.to_h
      amount = BigDecimal(token["amount"].to_s.presence || "0")
      price = token["price"]

      price_usd = if price.is_a?(Hash)
        BigDecimal((price["USD"] || price[:USD] || 0).to_s)
      else
        BigDecimal(price.to_s.presence || "0")
      end

      (amount * price_usd)
    rescue ArgumentError
      0.to_d
    end

    def normalize_tokens(tokens)
      Array(tokens).filter_map do |token|
        token = token.to_h
        next if token["amount"].to_f.zero?

        {
          "coinId" => token["coinId"] || token["id"],
          "symbol" => token["symbol"],
          "name" => token["name"],
          "amount" => token["amount"].to_s,
          "value_usd" => token_value_usd(token).to_s("F"),
          "imgUrl" => token["imgUrl"]
        }
      end
    end
end
