# Roda cada gerador de insight para uma familia. Um gerador que falha e logado e
# pulado, entao um sinal ruim nunca bloqueia o resto da execucao noturna. O
# resultado registra quais tipos de insight foram produzidos por geradores que
# rodaram ate o fim -- o job so expira insights obsoletos desses tipos, entao um
# gerador que quebra nunca pode apagar seus insights saudaveis.
class Insight::GeneratorRegistry
  GENERATORS = [
    Insight::Generators::SpendingAnomalyGenerator,
    Insight::Generators::NetWorthMilestoneGenerator,
    Insight::Generators::SubscriptionAuditGenerator,
    Insight::Generators::SavingsRateChangeGenerator,
    Insight::Generators::IdleCashGenerator
  ].freeze

  Result = Data.define(:insights, :succeeded_types)

  def initialize(family)
    @family = family
  end

  def generate_all
    insights = []
    succeeded_types = []

    GENERATORS.each do |generator_class|
      insights.concat(generator_class.new(family).generate)
      succeeded_types.concat(generator_class.produced_types)
    rescue => e
      Rails.logger.error(
        "Insight::GeneratorRegistry: #{generator_class.name} failed for family " \
        "#{family.id}: #{e.class}: #{e.message}"
      )
    end

    Result.new(insights: insights, succeeded_types: succeeded_types)
  end

  private
    attr_reader :family
end
