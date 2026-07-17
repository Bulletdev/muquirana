# Celebra o patrimonio liquido da familia cruzando um marco de numero redondo
# nos ultimos 30 dias. O dedup_key e o proprio valor do marco, entao uma linha
# de marco e reutilizada para sempre: uma dispensa e permanente, e so um
# cair-abaixo-e-recruzar dentro de uma janela de 30 dias pode ressurgir uma
# linha expirada.
class Insight::Generators::NetWorthMilestoneGenerator < Insight::Generator
  produces "net_worth_milestone"

  # Marcos em unidades de moeda da familia. Recalibrados para BRL: os degraus em
  # dolar/euro seriam pequenos demais em reais. A primeira faixa realista de
  # patrimonio no Brasil comeca na casa das dezenas de milhares de reais.
  MILESTONES = [
    50_000, 100_000, 250_000, 500_000, 1_000_000,
    2_500_000, 5_000_000, 10_000_000, 25_000_000, 50_000_000
  ].freeze

  def generate
    series = balance_sheet.net_worth_series(period: Period.last_30_days)
    values = series.values
    return [] if values.size < 2

    current = money_amount(values.last.value)
    previous = money_amount(values.first.value)
    return [] if current <= previous

    milestone = MILESTONES.select { |m| previous < m && current >= m }.max
    return [] unless milestone

    [
      build_insight(
        insight_type: "net_worth_milestone",
        priority: "high",
        title: I18n.t("insights.titles.net_worth_milestone", milestone: format_whole_money(milestone)),
        template_key: "net_worth_milestone",
        facts: {
          milestone: format_whole_money(milestone),
          net_worth: format_money(current)
        },
        # O marco sozinho e o sinal. O patrimonio em si oscila diariamente pelos
        # ~30 dias que o cruzamento fica na janela da serie -- guarda-lo aqui
        # reescreveria o body e ressuscitaria dispensas toda noite.
        metadata: {
          milestone: milestone
        },
        period: Period.last_30_days,
        dedup_key: "net_worth_milestone:#{milestone}"
      )
    ]
  end

  private
    def money_amount(value)
      (value.respond_to?(:amount) ? value.amount : value).to_d
    end

    def format_whole_money(amount)
      Money.new(amount, family.currency).format(precision: 0)
    end
end
