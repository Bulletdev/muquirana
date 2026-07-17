# Aponta saldos de caixa consideraveis que ficaram parados por um tempo. Baixa
# prioridade por design -- e um empurraozinho, nao um alerta. O dedup_key gira
# mensalmente para que um empurrao dispensado fique sumido pelo resto do mes.
class Insight::Generators::IdleCashGenerator < Insight::Generator
  produces "idle_cash"

  # Limiar em unidades de moeda da familia. Recalibrado para BRL: R$ 5.000 (o
  # limiar original em dolar/euro) seria trivial em reais. R$ 20.000 parado sem
  # movimento por dois meses ja e o suficiente para render em conta remunerada.
  MIN_BALANCE = 20_000
  IDLE_DAYS = 60
  MAX_INSIGHTS = 2

  def generate
    idle_accounts.first(MAX_INSIGHTS).map do |account|
      build_insight(
        insight_type: "idle_cash",
        priority: "low",
        title: I18n.t("insights.titles.idle_cash", account: account.name),
        template_key: "idle_cash",
        facts: {
          account: account.name,
          balance: format_money(account.balance),
          idle_days: IDLE_DAYS
        },
        metadata: {
          account_id: account.id,
          balance: round(account.balance, 0)
        },
        dedup_key: "idle_cash:#{account.id}:#{month_token}"
      )
    end
  end

  private
    # Ordenado para que a escolha seja estavel entre execucoes -- uma relacao sem
    # ordem poderia empurrar um par diferente de contas a cada noite, agitando o
    # feed.
    def idle_accounts
      family.accounts.visible
        .where(accountable_type: "Depository", currency: family.currency)
        .where("balance >= ?", MIN_BALANCE)
        .where.not(id: Entry.where("date >= ?", IDLE_DAYS.days.ago.to_date).select(:account_id))
        .order(balance: :desc)
    end
end
