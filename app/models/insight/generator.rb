# Classe base dos geradores de insight. Subclasses computam um sinal financeiro
# em Ruby puro e retornam registros GeneratedInsight -- so numeros, sem prosa. A
# prosa (`body`) e escrita depois por Insight::BodyWriter, e so quando o insight
# e novo ou seus numeros mudaram, entao re-execucoes noturnas nao re-invocam o
# LLM para insights inalterados.
class Insight::Generator
  # `facts` serve tanto como args de interpolacao i18n para o fallback de
  # template quanto como o material de grounding entregue ao redator LLM.
  # `metadata` e o que o job compara entre execucoes para decidir se um insight
  # mudou -- mantenha seus valores como primitivos JSON (floats, strings, datas
  # ISO) para que as comparacoes sejam estaveis.
  GeneratedInsight = Data.define(
    :insight_type,
    :priority,
    :title,
    :template_key,
    :facts,
    :metadata,
    :currency,
    :period_start,
    :period_end,
    :dedup_key
  )

  class << self
    # Declara os valores de insight_type que este gerador pode emitir. O job usa
    # isso para expirar insights obsoletos: um insight visivel cujo tipo
    # pertence a um gerador que rodou com sucesso, mas cujo dedup_key nao foi
    # regenerado, teve sua condicao encerrada.
    def produces(*types)
      @produced_types = types.flatten.map(&:to_s)
    end

    def produced_types
      @produced_types || []
    end
  end

  def initialize(family)
    @family = family
  end

  def generate
    raise NotImplementedError
  end

  private
    attr_reader :family

    def income_statement
      @income_statement ||= IncomeStatement.new(family)
    end

    def balance_sheet
      @balance_sheet ||= BalanceSheet.new(family)
    end

    # O Muquirana nao tem Period.current_month_for/last_month_for; estes helpers
    # entregam o mes-calendario completo (do primeiro ao ultimo dia), que e o que
    # os geradores esperam para projetar ritmo mensal.
    def current_month_period
      Period.custom(
        start_date: Date.current.beginning_of_month,
        end_date: Date.current.end_of_month
      )
    end

    def last_month_period
      start_date = Date.current.beginning_of_month - 1.month
      Period.custom(start_date: start_date, end_date: start_date.end_of_month)
    end

    def build_insight(insight_type:, priority:, title:, template_key:, facts:, dedup_key:, metadata:, period: nil)
      GeneratedInsight.new(
        insight_type: insight_type,
        priority: priority,
        title: title,
        template_key: template_key,
        facts: facts,
        metadata: metadata,
        currency: family.currency,
        period_start: period&.start_date,
        period_end: period&.end_date,
        dedup_key: dedup_key
      )
    end

    def format_money(amount)
      Money.new(amount, family.currency).format
    end

    # Normaliza resultados de matematica BigDecimal/Rational para que a metadata
    # sobreviva a um round-trip jsonb sem mudar (BigDecimal#as_json vira string,
    # o que faria toda execucao noturna parecer uma mudanca material).
    def round(amount, precision = 2)
      amount.to_f.round(precision)
    end

    def month_token(date = Date.current)
      date.strftime("%Y-%m")
    end

    # Formata um numero negativo com hifen para interpolacao em prosa de
    # template/LLM. Mantenha os numericos crus em `metadata`.
    def signed_number(value)
      value.negative? ? "-#{value.abs}" : value.to_s
    end
end
