class InsightsController < ApplicationController
  before_action :set_insight, only: %i[dismiss undismiss]

  def index
    load_feed
    @breadcrumbs = [ [ t("breadcrumbs.home"), root_path ], [ t("insights.index.title"), nil ] ]

    # Ver o feed e o que "ler" significa aqui; o badge de Novo para esta
    # renderizacao vem do @unread_ids capturado acima. O prefetch de hover do
    # Turbo bate neste GET antes do usuario navegar de fato, entao pula a
    # escrita para requisicoes de prefetch ou os badges limpariam no hover.
    unless prefetch_request?
      Current.family.insights.active.update_all(status: "read", read_at: Time.current, updated_at: Time.current)
    end
  end

  def dismiss
    @insight.dismiss!

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_back_or_to insights_path }
    end
  end

  def undismiss
    @insight.undismiss!
    load_feed

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_back_or_to insights_path }
    end
  end

  def refresh
    GenerateInsightsJob.perform_later(family_id: Current.family.id)

    respond_to do |format|
      # Troca o botao para o estado pendente; o job transmite a lista atualizada
      # e o botao ocioso de volta quando termina.
      format.turbo_stream
      format.html { redirect_to insights_path, notice: t("insights.refresh.queued") }
    end
  end

  private
    def set_insight
      @insight = Current.family.insights.find(params[:id])
    end

    def load_feed
      @insights = Current.family.insights.visible.ordered.to_a
      @unread_ids = @insights.select(&:active?).map(&:id).to_set
    end

    # O Turbo envia X-Sec-Purpose (a spec de fetch proibe setar Sec-Purpose via
    # JS) nas requisicoes de prefetch por hover.
    def prefetch_request?
      request.headers["X-Sec-Purpose"] == "prefetch" || request.headers["Sec-Purpose"].to_s.include?("prefetch")
    end
end
