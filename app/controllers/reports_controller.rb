# Dashboard de relatorios (US-10).
#
# Reune, numa unica pagina, indicadores que ja existiam espalhados pelo app
# (patrimonio via BalanceSheet, gastos/receitas por categoria via
# IncomeStatement, desempenho do orcamento via Budget) em secoes que o usuario
# pode colapsar e reordenar. As preferencias ficam em users.preferences.
#
# Nao ha camada de permissao por conta: tudo passa por Current.family, e os
# models ja respeitam accounts.exclude_from_reports.
class ReportsController < ApplicationController
  include Periodable

  # Export CSV (Onda 1): a action e publica no sentido de nao exigir sessao -- a
  # autenticacao (sessao OU api key) e feita em authenticate_for_export. Tambem
  # pulamos o gate de onboarding/upgrade, que redireciona para telas de HTML e
  # quebraria um download por API key (ex.: Google Sheets / IMPORTDATA).
  skip_authentication only: :export_transactions
  skip_before_action :require_onboarding_and_upgrade, only: :export_transactions
  before_action :authenticate_for_export, only: :export_transactions

  def index
    load_report_data
    @reports_sections = build_reports_sections
  end

  # Versao para impressao: mesmas secoes, sempre expandidas, sem cromo do app.
  def print
    load_report_data
    @reports_sections = build_reports_sections
    render layout: "print"
  end

  # Persiste ordem/colapso das secoes. Chamada via fetch pelos controllers
  # Stimulus (reports-section / reports-sortable).
  def update_preferences
    if Current.user.update_reports_preferences(preferences_params)
      head :ok
    else
      head :unprocessable_entity
    end
  end

  # Export CSV das transacoes da familia (Onda 1). Atende o botao na tela de
  # transacoes (sessao) e integracoes externas via API key (?api_key= / X-Api-Key).
  def export_transactions
    search = Transaction::Search.new(Current.family, filters: search_filters)
    exporter = Transaction::CsvExporter.new(search.transactions_scope, family: Current.family)

    send_data exporter.generate,
              filename: exporter.filename,
              type: "text/csv",
              disposition: "attachment"
  end

  private
    # Reaproveita os filtros ja existentes da tela de transacoes
    # (Transaction::Search): periodo (start_date/end_date), busca textual,
    # categorias, contas, tags, tipos e valor.
    def search_filters
      params.fetch(:q, {})
            .permit(
              :start_date, :end_date, :search, :amount,
              :amount_operator, :active_accounts_only,
              accounts: [], account_ids: [],
              categories: [], merchants: [], types: [], tags: []
            )
            .to_h
            .compact_blank
    end

    # Autenticacao do export: aceita sessao (usuario logado) OU api key.
    def authenticate_for_export
      if api_key_present?
        authenticate_with_api_key
      else
        authenticate_user!
      end
    end

    def api_key_present?
      params[:api_key].present? || request.headers["X-Api-Key"].present?
    end

    def authenticate_with_api_key
      api_key_value = params[:api_key].presence || request.headers["X-Api-Key"].presence

      @api_key = ApiKey.find_by_value(api_key_value)

      unless @api_key&.active?
        return render plain: "Invalid or expired API key", status: :unauthorized
      end

      # Respeita o escopo de leitura (read_write inclui read).
      unless @api_key.scopes&.intersect?(%w[read read_write])
        return render plain: "API key does not have read permission", status: :forbidden
      end

      @api_key.update_last_used!

      # Monta um Current.session efemero (nao persistido) para que Current.user e
      # Current.family funcionem sem reaproveitar uma sessao web existente.
      Current.session = @api_key.user.sessions.build(
        user_agent: request.user_agent,
        ip_address: request.ip
      )

      if Current.family.nil?
        render plain: "User does not have an associated family", status: :unprocessable_entity
      end
    end

    def load_report_data
      @balance_sheet = Current.family.balance_sheet
      @income_statement = Current.family.income_statement

      @income_totals = @income_statement.income_totals(period: @period)
      @expense_totals = @income_statement.expense_totals(period: @period)

      @budget = current_budget
      @budget_performance = build_budget_performance(@budget)

      @has_accounts = Current.family.accounts.visible.any?
      @has_transactions = Current.family.transactions.visible.any?
    end

    # Orcamento do mes corrente. find_or_bootstrap devolve nil quando a data cai
    # fora da janela valida (familia sem historico), entao tratamos ausencia.
    def current_budget
      Budget.find_or_bootstrap(Current.family, start_date: Date.current.beginning_of_month)
    end

    # Monta os dados de desempenho por categoria de orcamento (parent apenas),
    # so para categorias que realmente tem verba alocada. Cada item traz o que a
    # view precisa: nome, cor, gasto, orcado, restante, % e status.
    def build_budget_performance(budget)
      return [] unless budget&.initialized?

      budget.budget_categories.reject(&:subcategory?).filter_map do |budget_category|
        budgeted = budget_category.budgeted_spending
        next if budgeted.blank? || budgeted.zero?

        actual = budget.budget_category_actual_spending(budget_category)
        remaining = budgeted - actual
        percent_used = budgeted.zero? ? 0 : (actual / budgeted.to_f * 100)

        {
          category_name: budget_category.category.name,
          category_color: budget_category.category.color,
          budgeted: budgeted,
          actual: actual,
          remaining: remaining,
          percent_used: percent_used,
          status: budget_status(percent_used)
        }
      end.sort_by { |item| -item[:percent_used] }
    end

    def budget_status(percent_used)
      if percent_used >= 100
        :over
      elsif percent_used >= 80
        :warning
      else
        :good
      end
    end

    # Descreve as secoes disponiveis e as ordena conforme a preferencia do
    # usuario. `visible: false` some da pagina sem apagar a preferencia de ordem.
    #
    # MVP da US-10: patrimonio, gastos por categoria e desempenho do orcamento.
    # TODO (fora do MVP): secoes de fluxo e performance de investimento e de
    # tendencias (trends). O Sure porta essas via InvestmentStatement /
    # InvestmentFlowStatement, models que a Muquirana ainda nao tem -- exigiriam
    # portar tambem essa camada de dominio antes das views. Ao adiciona-las,
    # basta incluir a chave em User::REPORTS_SECTIONS e um item aqui.
    def build_reports_sections
      all_sections = {
        "net_worth" => {
          key: "net_worth",
          title: t("reports.sections.net_worth"),
          partial: "reports/net_worth",
          locals: { balance_sheet: @balance_sheet, period: @period },
          visible: @has_accounts
        },
        "category_breakdown" => {
          key: "category_breakdown",
          title: t("reports.sections.category_breakdown"),
          partial: "reports/category_breakdown",
          locals: { income_totals: @income_totals, expense_totals: @expense_totals },
          visible: @has_transactions
        },
        "budget_performance" => {
          key: "budget_performance",
          title: t("reports.sections.budget_performance"),
          partial: "reports/budget_performance",
          locals: { budget: @budget, budget_performance: @budget_performance },
          visible: @budget_performance.any?
        }
      }

      Current.user.reports_section_order.filter_map { |key| all_sections[key] }
    end

    def preferences_params
      prefs = params.require(:preferences)

      {}.tap do |permitted|
        if prefs[:reports_collapsed_sections].present?
          # Permite apenas as secoes conhecidas (nunca chaves arbitrarias) e
          # guarda so booleanos.
          collapsed = prefs.require(:reports_collapsed_sections)
            .permit(*User::REPORTS_SECTIONS)
            .to_h
          permitted["reports_collapsed_sections"] = collapsed
            .transform_values { |v| ActiveModel::Type::Boolean.new.cast(v) }
        end

        if prefs[:reports_section_order].present?
          order = Array(prefs[:reports_section_order]).map(&:to_s)
          permitted["reports_section_order"] = order & User::REPORTS_SECTIONS
        end
      end
    end
end
