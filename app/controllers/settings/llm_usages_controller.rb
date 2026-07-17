class Settings::LlmUsagesController < ApplicationController
  layout "settings"

  def show
    @breadcrumbs = [
      [ t("breadcrumbs.home"), root_path ],
      [ t("breadcrumbs.llm_usage"), nil ]
    ]
    @family = Current.family

    # Intervalo de datas via params, com padrao de 30 dias.
    @end_date  = safe_parse_date(params[:end_date])  || Date.current
    @start_date = safe_parse_date(params[:start_date]) || (@end_date - 30.days)
    if @start_date > @end_date
      @start_date, @end_date = @end_date - 30.days, @end_date
    end

    @llm_usages = @family.llm_usages
                         .for_date_range(@start_date.beginning_of_day, @end_date.end_of_day)
                         .recent
                         .limit(100)

    @statistics = LlmUsage.statistics_for_family(
      @family,
      start_date: @start_date.beginning_of_day,
      end_date: @end_date.end_of_day
    )
  end

  private
    def safe_parse_date(s)
      Date.iso8601(s)
    rescue ArgumentError, TypeError
      nil
    end
end
