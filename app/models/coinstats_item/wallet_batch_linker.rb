# frozen_string_literal: true

# Vincula UM endereco publico em VARIAS blockchains de uma vez.
#
# Motivacao (UX): carteiras EVM (MetaMask/Rabby/etc.) usam o MESMO endereco
# `0x...` em Ethereum, Polygon, Arbitrum, Optimism, Base, BNB... Obrigar o usuario
# a repetir o mesmo endereco chain por chain e ruim. Aqui ele cola o endereco uma
# vez, marca as chains e a gente cria as contas onde houver saldo.
#
# Eficiencia de credito (plano free do CoinStats): os saldos das chains sao
# buscados numa UNICA chamada em lote (Importer#build_wallet_snapshots). Chains
# sem token nem DeFi sao PULADAS (nao viram conta nem erro) -- entao marcar chains
# a mais e barato e inofensivo.
class CoinstatsItem::WalletBatchLinker
  attr_reader :coinstats_item, :address, :blockchains, :import_empty

  # linked: chains que viraram conta; empty: chains sem saldo (puladas).
  # Quando success? e false MAS errors esta vazio e empty tem chains, e o sinal de
  # "nenhum saldo encontrado" -- o controller oferece importar mesmo assim.
  Result = Struct.new(:success?, :linked, :empty, :errors, keyword_init: true)

  # @param import_empty [Boolean] quando true, cria a conta (zerada) mesmo nas
  #   chains sem saldo -- o usuario confirmou "importar mesmo assim, sincronizo
  #   depois" (carteira nova ou fundos ainda nao indexados pelo CoinStats).
  def initialize(coinstats_item, address:, blockchains:, import_empty: false)
    @coinstats_item = coinstats_item
    @address = address.to_s.strip
    @blockchains = Array(blockchains).map { |b| b.to_s.strip.downcase }.reject(&:blank?).uniq
    @import_empty = import_empty
  end

  def link
    return failure([ "Informe o endereco e ao menos uma blockchain" ]) if address.blank? || blockchains.empty?

    provider = coinstats_item.coinstats_provider
    return failure([ "Chave da API do CoinStats nao configurada" ]) unless provider

    snapshots = importer.build_wallet_snapshots(address: address, blockchains: blockchains)

    linked = []
    empty = []

    blockchains.each do |blockchain|
      snapshot = snapshots[blockchain]
      has_balance = snapshot.present? && (snapshot[:tokens].any? || snapshot[:defi_positions].any?)

      if has_balance || import_empty
        # Sem saldo + import_empty: cria a conta zerada; um sync futuro a preenche.
        CoinstatsItem::WalletLinker.persist(
          coinstats_item,
          address: address,
          blockchain: blockchain,
          snapshot: snapshot.presence || empty_snapshot
        )
        linked << blockchain
      else
        empty << blockchain
      end
    end

    # Nada tinha saldo e o usuario ainda nao confirmou importar mesmo assim:
    # devolve sem erro, so com as chains vazias -- o controller oferece a opcao.
    return offer_import(empty) if linked.empty?

    coinstats_item.sync_later

    Result.new(success?: true, linked: linked, empty: empty, errors: [])
  rescue Provider::Coinstats::Error
    # Erros tipados (creditos/rate-limit/auth) sobem para o controller traduzir.
    raise
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error("CoinstatsItem::WalletBatchLinker - falha ao vincular carteiras: #{e.message}")
    failure([ e.message ])
  end

  private
    def importer
      @importer ||= CoinstatsItem::Importer.new(coinstats_item, coinstats_provider: coinstats_item.coinstats_provider)
    end

    def empty_snapshot
      { total_usd: 0.to_d, tokens: [], defi_positions: [] }
    end

    def offer_import(empty)
      Result.new(success?: false, linked: [], empty: empty, errors: [])
    end

    def failure(errors)
      Result.new(success?: false, linked: [], empty: [], errors: errors)
    end
end
