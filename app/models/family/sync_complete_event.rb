class Family::SyncCompleteEvent
  attr_reader :family

  def initialize(family)
    @family = family
  end

  def broadcast
    family.broadcast_replace(
      target: "balance-sheet",
      partial: "pages/dashboard/balance_sheet",
      locals: { balance_sheet: family.balance_sheet }
    )

    family.broadcast_replace(
      target: "net-worth-chart",
      partial: "pages/dashboard/net_worth_chart",
      locals: { balance_sheet: family.balance_sheet, period: Period.last_30_days }
    )

    # Gancho pos-sync: agenda a identificacao de recorrencias (debounce + advisory
    # lock cuidam de concorrencia e de rodar so uma vez apos os syncs terminarem).
    # E side-effect: qualquer falha e logada e nunca quebra o broadcast do sync.
    begin
      RecurringTransaction.identify_patterns_for(family)
    rescue => e
      Rails.logger.error("Falha ao agendar identificacao de recorrencias: #{e.message}")
    end
  end
end
