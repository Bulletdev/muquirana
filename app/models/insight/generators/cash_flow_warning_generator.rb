# Projeta o caixa combinado da familia (contas Depository) 30 dias a frente,
# sobrepondo as transacoes recorrentes conhecidas a uma linha de base
# estatistica de gasto diario, e avisa quando o saldo projetado cai abaixo do
# limiar. Convencao de sinal do Maybe: amount positivo e saida (despesa), amount
# negativo e entrada (renda); por isso subtraimos o amount do saldo.
class Insight::Generators::CashFlowWarningGenerator < Insight::Generator
  produces "cash_flow_warning"

  # Limiar em unidades da moeda da familia. Recalibrado para BRL: R$ 500 (o valor
  # original em dolar/euro) e baixo demais para servir de colchao de caixa em
  # reais. R$ 2.000 e um piso minimo mais realista antes de acender o alerta.
  LOW_BALANCE_THRESHOLD = 2_000
  HORIZON_DAYS = 30

  ProjectedOutflow = Data.define(:date, :amount)

  def generate
    accounts = cash_accounts
    return [] if accounts.empty?

    starting_balance = accounts.sum(:balance).to_d
    entries = upcoming_recurring_entries
    recurring_by_date = entries.group_by(&:date)

    # As contas recorrentes tambem entram na mediana mensal -- subtraia-as para
    # nao conta-las duas vezes ao espalhar o restante pelo horizonte.
    median_monthly_expense = income_statement.median_expense(interval: "month").to_d
    return [] if median_monthly_expense <= 0 && entries.empty?

    recurring_expense_total = entries.sum { |e| [ e.amount, 0.to_d ].max }
    other_daily_spend = [ median_monthly_expense - recurring_expense_total, 0.to_d ].max / HORIZON_DAYS

    balance = starting_balance
    low_point = starting_balance
    low_date = Date.current

    (1..HORIZON_DAYS).each do |offset|
      date = Date.current + offset
      balance -= other_daily_spend
      recurring_by_date.fetch(date, []).each { |e| balance -= e.amount }

      if balance < low_point
        low_point = balance
        low_date = date
      end
    end

    return [] if low_point >= LOW_BALANCE_THRESHOLD

    template_key = low_point.negative? ? "cash_flow_warning.negative" : "cash_flow_warning.low"

    [
      build_insight(
        insight_type: "cash_flow_warning",
        priority: low_point.negative? ? "high" : "medium",
        title: I18n.t("insights.titles.#{template_key}"),
        template_key: template_key,
        facts: {
          projected_low: format_money(low_point),
          projected_low_date: I18n.l(low_date),
          current_balance: format_money(starting_balance),
          horizon_days: HORIZON_DAYS
        },
        # Saldos e datas projetadas mudam a cada transacao, entao valores exatos
        # aqui pareceriam mudanca material toda noite -- reescrevendo o body e
        # ressuscitando dispensas. So a severidade e um balde grosso do ponto
        # baixo sao materiais; os valores de exibicao ficam em `facts`. Balde de
        # R$ 1.000 (era R$ 250 no Sure) para acompanhar a escala do BRL.
        metadata: {
          negative: low_point.negative?,
          projected_low_bucket: (round(low_point, 0).to_i / 1_000) * 1_000
        },
        period: Period.custom(start_date: Date.current, end_date: Date.current + HORIZON_DAYS),
        dedup_key: "cash_flow_warning:#{month_token}"
      )
    ]
  end

  private
    def cash_accounts
      family.accounts.visible.where(accountable_type: "Depository", currency: family.currency)
    end

    # Ocorrencias projetadas das recorrencias conhecidas dentro do horizonte. O
    # RecurringTransaction do Muquirana nao modela transferencias, entao nao ha o
    # que excluir; valores em outra moeda nao podem ser aplicados a um saldo na
    # moeda da familia sem cotacao, entao ficam de fora. Uma recorrencia mensal
    # tem no maximo uma ocorrencia dentro dos 30 dias: sua next_expected_date.
    def upcoming_recurring_entries
      family.recurring_transactions
        .active
        .where(currency: family.currency)
        .where(next_expected_date: Date.current..(Date.current + HORIZON_DAYS))
        .map { |rt| ProjectedOutflow.new(date: rt.next_expected_date, amount: rt.amount.to_d) }
    end
end
