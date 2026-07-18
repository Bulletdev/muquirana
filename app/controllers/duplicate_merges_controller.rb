# US-03: merge manual de transacoes duplicadas em reimportacao (CSV/OFX).
# Sugere lancamentos potencialmente duplicados do mesmo lancamento e permite
# mesclar ou dispensar a sugestao. Escopo por Current.family (sem camada de
# permissao do Sure).
class DuplicateMergesController < ApplicationController
  before_action :set_transaction

  def new
    @limit = 10
    @offset = [ (params[:offset] || 0).to_i, 0 ].max

    # Busca um a mais para saber se ha mais resultados.
    candidates = @transaction.duplicate_candidates(limit: @limit + 1, offset: @offset).to_a
    @has_more = candidates.size > @limit
    @candidates = candidates.first(@limit)

    @range_start = @offset + 1
    @range_end = @offset + @candidates.count
  end

  def create
    duplicate_entry = find_eligible_duplicate(merge_params[:duplicate_entry_id])

    unless duplicate_entry
      redirect_back_or_to transactions_path, alert: t(".invalid")
      return
    end

    if @transaction.merge_duplicate!(duplicate_entry)
      redirect_back_or_to transactions_path, notice: t(".success")
    else
      redirect_back_or_to transactions_path, alert: t(".failure")
    end
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotDestroyed,
         ActiveRecord::Deadlocked, ActiveRecord::LockWaitTimeout => e
    Rails.logger.error("Falha ao mesclar transacao duplicada: #{e.message}")
    redirect_back_or_to transactions_path, alert: t(".failure")
  end

  # Dispensa a sugestao sem alterar dado nenhum. Os dois lancamentos continuam
  # intactos: e o caminho correto quando a "duplicata" e, na verdade, uma
  # colisao legitima de dois lancamentos identicos de verdade.
  def dismiss
    redirect_back_or_to transactions_path, notice: t(".success")
  end

  private
    def set_transaction
      @entry = Current.family.entries.find(params[:transaction_id])
      @transaction = @entry.entryable

      unless @transaction.is_a?(Transaction)
        redirect_to transactions_path, alert: t("duplicate_merges.errors.not_a_transaction")
      end
    end

    # Garante que o duplicado escolhido e mesmo um candidato elegivel (mesma
    # conta, mesma moeda, nao e o proprio lancamento), reusando a heuristica.
    def find_eligible_duplicate(entry_id)
      return nil if entry_id.blank?

      @transaction.duplicate_candidates(limit: 1_000).find_by(id: entry_id)
    end

    def merge_params
      params.require(:duplicate_merge).permit(:duplicate_entry_id)
    end
end
