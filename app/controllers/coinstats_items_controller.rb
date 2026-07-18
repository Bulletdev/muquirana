class CoinstatsItemsController < ApplicationController
  before_action :set_coinstats_item, only: %i[destroy sync link_wallet]

  # Lista estatica de chains usada quando a API nao responde (creditos/rate-limit)
  # -- o usuario ainda consegue vincular as chains mais comuns. connectionIds
  # conforme a OpenAPI do CoinStats.
  FALLBACK_BLOCKCHAINS = [
    [ "Ethereum", "ethereum" ],
    [ "Bitcoin", "bitcoin" ],
    [ "BNB Smart Chain", "binance-smart-chain" ],
    [ "Polygon", "polygon" ],
    [ "Arbitrum", "arbitrum" ],
    [ "Optimism", "optimism" ],
    [ "Avalanche", "avalanche" ],
    [ "Base", "base" ],
    [ "Solana", "solana" ]
  ].freeze

  def new
    @coinstats_item = Current.family.coinstats_items.build
  end

  def create
    @coinstats_item = Current.family.create_coinstats_item!(
      api_key: coinstats_item_params[:api_key],
      item_name: coinstats_item_params[:name]
    )

    # Chave salva: agora da para popular o dropdown de chains com a API.
    redirect_to link_wallet_coinstats_item_path(@coinstats_item)
  rescue ActiveRecord::RecordInvalid => e
    @coinstats_item = e.record
    render :new, status: :unprocessable_entity
  end

  # GET: formulario de vinculo (endereco + dropdown de chain).
  # POST: busca saldos + DeFi e cria a Account agregada da carteira.
  def link_wallet
    return render_link_wallet_form unless request.post?

    address = link_wallet_params[:address]
    blockchains = Array(link_wallet_params[:blockchain])
    import_empty = ActiveModel::Type::Boolean.new.cast(link_wallet_params[:import_empty])

    result = @coinstats_item.link_wallets!(
      address: address,
      blockchains: blockchains,
      import_empty: import_empty
    )

    if result.success?
      redirect_to accounts_path, notice: link_wallet_notice(result)
    elsif result.errors.any?
      render_link_wallet_form(alert: result.errors.to_sentence)
    else
      # Nenhum saldo encontrado nas chains escolhidas -- oferece importar mesmo
      # assim (o usuario sincroniza depois). Reapresenta o form ja preenchido.
      render_link_wallet_form(
        import_empty_chains: result.empty,
        submitted_address: address,
        submitted_blockchains: blockchains
      )
    end
  rescue Provider::Coinstats::Error => e
    render_link_wallet_form(alert: friendly_error_message(e))
  end

  def destroy
    @coinstats_item.destroy_later
    redirect_to accounts_path, notice: t(".success")
  end

  def sync
    @coinstats_item.sync_later unless @coinstats_item.syncing?

    respond_to do |format|
      format.html { redirect_back_or_to accounts_path }
      format.json { head :ok }
    end
  end

  private
    # So busca as chains (custa credito) quando REALMENTE vamos renderizar o form.
    # import_empty_chains/submitted_*: preenchem o prompt "importar mesmo sem saldo"
    # e o reenvio (endereco + chains marcadas ja preservados).
    def render_link_wallet_form(alert: nil, import_empty_chains: nil, submitted_address: nil, submitted_blockchains: nil)
      @blockchain_options = blockchain_options_for(@coinstats_item)
      @import_empty_chains = import_empty_chains
      @submitted_address = submitted_address
      @submitted_blockchains = Array(submitted_blockchains)
      flash.now[:alert] = alert if alert.present?
      status = (alert.present? || import_empty_chains.present?) ? :unprocessable_entity : :ok
      render :link_wallet, status: status
    end

    def set_coinstats_item
      @coinstats_item = Current.family.coinstats_items.find(params[:id])
    end

    def coinstats_item_params
      params.require(:coinstats_item).permit(:name, :api_key)
    end

    def link_wallet_params
      params.require(:coinstats_item).permit(:address, :import_empty, blockchain: [])
    end

    # Mensagem de sucesso: quantas carteiras entraram e, se houver, quais chains
    # foram puladas por nao ter saldo (transparencia -- o usuario marcou e nada
    # apareceu).
    def link_wallet_notice(result)
      notice = t(".success", count: result.linked.size)

      if result.empty.any?
        skipped = result.empty.map(&:capitalize).to_sentence
        notice = "#{notice} #{t(".skipped_empty", chains: skipped)}"
      end

      notice
    end

    # Busca as chains suportadas via API (autoritativo). Cai na lista estatica se
    # a API nao responder (creditos/rate-limit/rede).
    def blockchain_options_for(item)
      provider = item.coinstats_provider
      return FALLBACK_BLOCKCHAINS unless provider

      options = provider.blockchain_options
      options.presence || FALLBACK_BLOCKCHAINS
    rescue Provider::Coinstats::Error
      FALLBACK_BLOCKCHAINS
    end

    def friendly_error_message(error)
      case error
      when Provider::Coinstats::CreditsExhaustedError
        t("coinstats_item.syncer.errors.credits_exhausted")
      when Provider::Coinstats::RateLimitError
        t("coinstats_item.syncer.errors.rate_limited")
      when Provider::Coinstats::AuthenticationError
        t("coinstats_item.syncer.errors.authentication")
      else
        t("coinstats_item.syncer.errors.api_error")
      end
    end
end
