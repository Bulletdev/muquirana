# frozen_string_literal: true

# Descobre e agrega as posicoes DeFi (staking, LP, yield farming) de uma carteira
# on-chain via CoinStats (GET /wallet/defi).
#
# Portado do CoinstatsItem::DefiAccountManager do Sure (we-promise/sure, AGPLv3),
# ADAPTADO a decisao de UX do Muquirana: em vez de criar uma Account por posicao
# DeFi (o que poluiria a lista de contas), este manager AGREGA o valor total das
# posicoes da carteira. Esse total entra no saldo da unica Account daquela
# carteira (endereco + chain). Cada posicao continua rastreada no snapshot para
# transparencia.
#
# Mantem o `build_account_id` do Sure (codifica a chain) na chave de cada posicao
# do snapshot, para nao colidir quando o mesmo endereco existe em varias chains
# EVM (ex.: Ethereum e Polygon).
class CoinstatsItem::DefiAccountManager
  attr_reader :coinstats_item, :provider

  Result = Struct.new(:total_usd, :positions, keyword_init: true)

  def initialize(coinstats_item, provider:)
    @coinstats_item = coinstats_item
    @provider = provider
  end

  # Busca e agrega o valor (em USD) de todas as posicoes DeFi da carteira.
  # @return [Result] total_usd (BigDecimal) e positions (Array<Hash> snapshot)
  def wallet_defi_value(address:, blockchain:)
    normalized_address = address.to_s.downcase
    normalized_blockchain = blockchain.to_s.downcase

    defi_data = provider.get_wallet_defi(address: address, connection_id: blockchain).to_h
    protocols = Array(defi_data["protocols"])

    positions = []

    protocols.each do |protocol|
      next unless protocol.is_a?(Hash)

      Array(protocol["investments"]).each do |investment|
        next unless investment.is_a?(Hash)

        Array(investment["assets"]).each do |asset|
          next unless asset.is_a?(Hash)
          next if asset["amount"].to_f.zero?
          next if asset["coinId"].blank? && asset["symbol"].blank?

          value_usd = total_value_usd(asset)
          positions << {
            "account_id" => build_account_id(protocol, investment, asset, blockchain: normalized_blockchain),
            "address" => normalized_address,
            "blockchain" => normalized_blockchain,
            "protocol_id" => protocol["id"],
            "protocol_name" => protocol["name"],
            "protocol_logo" => protocol["logo"],
            "investment_type" => investment["name"],
            "coinId" => asset["coinId"],
            "symbol" => asset["symbol"],
            "amount" => asset["amount"],
            "title" => asset["title"],
            "value_usd" => value_usd.to_s("F")
          }
        end
      end
    end

    Result.new(total_usd: positions.sum { |p| BigDecimal(p["value_usd"]) }, positions: positions)
  end

  private
    # A DeFi API devolve asset.price como um TotalValueDto (valor total da posicao,
    # nao preco por token). Aceita tanto Hash { "USD" => ... } quanto escalar.
    def total_value_usd(asset)
      price = asset["price"]

      raw = if price.is_a?(Hash)
        price["USD"] || price[:USD] || 0
      else
        price
      end

      BigDecimal(raw.to_s)
    rescue ArgumentError
      0.to_d
    end

    # Chave estavel e unica por posicao DeFi (codifica a chain -- copiado do Sure).
    # Formato: "defi:<chain>:<protocol_id>[:<investment_type>]:<coin_id>:<title>"
    def build_account_id(protocol, investment, asset, blockchain:)
      chain = blockchain.to_s.downcase.gsub(/\s+/, "_").presence || "unknown"
      protocol_id = protocol["id"].to_s.downcase.gsub(/\s+/, "_").presence || "unknown"
      coin_id = (asset["coinId"] || asset["symbol"]).to_s.downcase
      title = asset["title"].to_s.downcase.gsub(/\s+/, "_").presence || "position"
      investment_type = investment["name"].to_s.downcase.gsub(/\s+/, "_").presence

      parts = [ "defi", chain, protocol_id, coin_id, title ]
      parts.insert(3, investment_type) if investment_type.present?
      parts.join(":")
    end
end
