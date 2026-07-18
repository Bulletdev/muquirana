# frozen_string_literal: true

# Vincula uma carteira on-chain (endereco publico + chain) ao CoinStats: busca os
# saldos de tokens + posicoes DeFi e materializa UMA Account agregada por carteira.
#
# Portado do CoinstatsItem::WalletLinker do Sure (we-promise/sure, AGPLv3),
# ADAPTADO a decisao de UX do Muquirana. O Sure criava uma Account POR TOKEN (e o
# DefiAccountManager, uma por posicao DeFi) -- muito ruido na lista de contas de
# quem tem uma carteira com dezenas de tokens/airdrops. Aqui criamos UMA unica
# Account cripto por carteira (endereco + chain), com o saldo = valor de todos os
# tokens + posicoes DeFi. Isso segue o mesmo molde do BinanceItem::Importer
# (uma conta "combined") e mantem a lista de contas limpa.
#
# A chave `account_id` do CoinstatsAccount codifica a chain
# ("wallet:<blockchain>:<address>"), preservando a unicidade multi-chain do Sure:
# o mesmo endereco em Ethereum e Polygon vira duas contas distintas.
class CoinstatsItem::WalletLinker
  attr_reader :coinstats_item, :address, :blockchain

  Result = Struct.new(:success?, :created, :account, :errors, keyword_init: true)

  # Cria/atualiza a Account a partir de um snapshot JA construido (ex.: pelo
  # WalletBatchLinker, que busca as chains em lote). Reusa a mesma logica de
  # persistencia do vinculo single-chain, sem refazer a chamada de saldos.
  def self.persist(coinstats_item, address:, blockchain:, snapshot:)
    new(coinstats_item, address: address, blockchain: blockchain).send(:create_wallet!, snapshot)
  end

  def initialize(coinstats_item, address:, blockchain:)
    @coinstats_item = coinstats_item
    @address = address.to_s.strip
    @blockchain = blockchain.to_s.strip
  end

  def link
    return failure([ "Endereco e chain sao obrigatorios" ]) if address.blank? || blockchain.blank?

    provider = coinstats_item.coinstats_provider
    return failure([ "Chave da API do CoinStats nao configurada" ]) unless provider

    snapshot = importer.build_wallet_snapshot(address: address, blockchain: blockchain)

    if snapshot[:tokens].empty? && snapshot[:defi_positions].empty?
      return failure([ "Nenhum token ou posicao DeFi encontrada para esta carteira" ])
    end

    account = create_wallet!(snapshot)
    coinstats_item.sync_later

    Result.new(success?: true, created: true, account: account, errors: [])
  rescue Provider::Coinstats::Error
    # Erros tipados (creditos/rate-limit/auth) sobem para o controller/syncer
    # traduzir em mensagem acionavel.
    raise
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error("CoinstatsItem::WalletLinker - falha ao vincular carteira: #{e.message}")
    failure([ e.message ])
  end

  private
    def importer
      @importer ||= CoinstatsItem::Importer.new(coinstats_item, coinstats_provider: coinstats_item.coinstats_provider)
    end

    def create_wallet!(snapshot)
      CoinstatsItem.transaction do
        coinstats_account = coinstats_item.coinstats_accounts.find_or_initialize_by(
          account_id: wallet_account_id,
          wallet_address: normalized_address
        )

        coinstats_account.assign_attributes(
          name: build_account_name,
          blockchain: normalized_blockchain,
          currency: "USD",
          current_balance: snapshot[:total_usd],
          institution_metadata: {
            "name" => coinstats_item.institution_name,
            "domain" => coinstats_item.institution_domain,
            "url" => coinstats_item.institution_url,
            "color" => coinstats_item.institution_color
          },
          raw_payload: {
            "address" => normalized_address,
            "blockchain" => normalized_blockchain,
            "tokens" => snapshot[:tokens],
            "defi_positions" => snapshot[:defi_positions],
            "total_usd" => snapshot[:total_usd].to_s,
            "fetched_at" => Time.current.iso8601
          }
        )
        coinstats_account.save!

        account = coinstats_item.family.accounts.create!(
          accountable: Crypto.new,
          name: coinstats_account.name,
          balance: 0,
          cash_balance: 0,
          currency: coinstats_item.family.currency,
          status: "active"
        )

        coinstats_account.ensure_account_provider!(account)
        account
      end
    end

    def build_account_name
      truncated = normalized_address.length > 10 ? "#{normalized_address.first(6)}...#{normalized_address.last(4)}" : normalized_address
      "#{blockchain.capitalize} (#{truncated})"
    end

    def wallet_account_id
      "wallet:#{normalized_blockchain}:#{normalized_address}"
    end

    def normalized_address
      @normalized_address ||= address.downcase
    end

    def normalized_blockchain
      @normalized_blockchain ||= blockchain.downcase
    end

    def failure(errors)
      Result.new(success?: false, created: false, account: nil, errors: errors)
    end
end
