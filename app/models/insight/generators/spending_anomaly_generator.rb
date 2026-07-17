# Sinaliza categorias-pai cujo ritmo de gasto no mes atual desvia da media dos
# tres meses completos anteriores.
class Insight::Generators::SpendingAnomalyGenerator < Insight::Generator
  produces "spending_anomaly"

  # Limiar em unidades de moeda da familia. Recalibrado para BRL: R$ 50 (o
  # original em dolar/euro) sinalizaria categorias irrelevantes em reais. R$ 200
  # de media mensal ja indica uma categoria com peso real no orcamento.
  MIN_BASELINE = 200
  MIN_ELAPSED_DAYS = 7        # cedo demais no mes = ruidoso demais para projetar
  DEVIATION_THRESHOLD_PCT = 25
  HIGH_PRIORITY_PCT = 50
  BASELINE_MONTHS = 3
  MAX_INSIGHTS = 3

  def generate
    period = current_month_period
    elapsed_days = (Date.current - period.start_date).to_i + 1
    return [] if elapsed_days < MIN_ELAPSED_DAYS

    current = category_spend(period)
    return [] if current.empty?

    baseline = baseline_spend(period)
    pace_factor = period.days.to_f / elapsed_days

    anomalies = current.filter_map do |category_id, data|
      baseline_amount = baseline[category_id]
      next unless baseline_amount && baseline_amount >= MIN_BASELINE

      projected = data[:total] * pace_factor
      deviation_pct = (projected - baseline_amount) / baseline_amount * 100
      next if deviation_pct.abs < DEVIATION_THRESHOLD_PCT

      { category_id: category_id, name: data[:name], projected: projected,
        baseline: baseline_amount, deviation_pct: deviation_pct }
    end

    anomalies
      .sort_by { |a| -a[:deviation_pct].abs }
      .first(MAX_INSIGHTS)
      .map { |anomaly| anomaly_insight(anomaly, period) }
  end

  private
    def anomaly_insight(anomaly, period)
      direction = anomaly[:deviation_pct].positive? ? "above" : "below"

      build_insight(
        insight_type: "spending_anomaly",
        priority: anomaly[:deviation_pct].abs >= HIGH_PRIORITY_PCT ? "high" : "medium",
        title: I18n.t("insights.titles.spending_anomaly.#{direction}", category: anomaly[:name]),
        template_key: "spending_anomaly.#{direction}",
        facts: {
          category: anomaly[:name],
          deviation_pct: round(anomaly[:deviation_pct].abs, 0).to_i,
          projected_spend: format_money(anomaly[:projected]),
          baseline_spend: format_money(anomaly[:baseline])
        },
        # A projecao se move toda noite por construcao (o gasto acumula e o fator
        # de ritmo encolhe conforme o mes passa), entao valores exatos aqui
        # reescreveriam o body e ressuscitariam dispensas toda noite. Bucketiza o
        # desvio; os numeros de exibicao vivem so em `facts`.
        metadata: {
          category_id: anomaly[:category_id],
          direction: direction,
          deviation_bucket: (round(anomaly[:deviation_pct].abs, 0).to_i / 25) * 25
        },
        period: period,
        dedup_key: "spending_anomaly:#{anomaly[:category_id]}:#{month_token(period.start_date)}"
      )
    end

    # { category_id => { name:, total: } } so para categorias-pai persistidas. O
    # gasto de subcategoria ja esta somado no total do pai, e a categoria
    # sintetica (nao-categorizado, sem id persistido) e ruidosa demais para
    # sinalizar.
    def category_spend(period)
      income_statement.expense_totals(period: period).category_totals.each_with_object({}) do |ct, totals|
        next if ct.category.id.nil? || ct.category.subcategory?
        next unless ct.total.positive?

        totals[ct.category.id] = { name: ct.category.name, total: ct.total.to_d }
      end
    end

    def baseline_spend(current_period)
      sums = Hash.new { |h, k| h[k] = 0.to_d }

      BASELINE_MONTHS.times do |i|
        start_date = current_period.start_date - (i + 1).months
        month = Period.custom(start_date: start_date, end_date: start_date + 1.month - 1.day)

        category_spend(month).each do |category_id, data|
          sums[category_id] += data[:total]
        end
      end

      sums.transform_values { |total| total / BASELINE_MONTHS }
    end
end
