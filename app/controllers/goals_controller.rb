class GoalsController < ApplicationController
  before_action :set_goal, only: %i[show edit update destroy]

  # Contas que podem financiar uma meta: depositos (poupanca/conta corrente)
  # e investimentos. O nucleo usa o SALDO da conta ligada.
  FUNDABLE_TYPES = %w[Depository Investment].freeze

  def index
    @goals = Current.family.goals.alphabetically.includes(:account).to_a
    @linkable_accounts = linkable_accounts
    @breadcrumbs = [
      [ t("breadcrumbs.home"), root_path ],
      [ t("goals.index.title"), nil ]
    ]
  end

  def show
    @breadcrumbs = [
      [ t("breadcrumbs.home"), root_path ],
      [ t("goals.index.title"), goals_path ],
      [ @goal.name, nil ]
    ]
  end

  def new
    @goal = Current.family.goals.new(
      color: Goal::COLORS.sample,
      currency: Current.family.currency
    )
    @linkable_accounts = linkable_accounts
  end

  def create
    @goal = Current.family.goals.new(goal_params)
    @goal.account = linkable_account(params.dig(:goal, :account_id))
    @goal.currency = @goal.account&.currency || Current.family.currency if @goal.currency.blank?

    if @goal.save
      redirect_to goals_path, notice: t(".success")
    else
      @linkable_accounts = linkable_accounts
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @linkable_accounts = linkable_accounts
  end

  def update
    @goal.assign_attributes(goal_params)
    # So troca a conta se veio account_id no request (senao mantem a atual);
    # sempre resolvida escopada na familia (linkable_account).
    if params.dig(:goal, :account_id).present?
      @goal.account = linkable_account(params[:goal][:account_id])
    end

    if @goal.save
      redirect_to goal_path(@goal), notice: t(".success")
    else
      @linkable_accounts = linkable_accounts
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @goal.destroy!
    redirect_to goals_path, notice: t(".success")
  end

  private
    def set_goal
      @goal = Current.family.goals.find(params[:id])
    end

    # account_id NAO entra no permit: um id de outra familia via mass-assignment
    # ligaria a meta a conta alheia (IDOR). A conta e resolvida em separado,
    # sempre escopada na familia atual (ver linkable_account).
    def goal_params
      params.require(:goal).permit(:name, :target_amount, :target_date, :color, :icon, :notes)
    end

    def linkable_account(id)
      return nil if id.blank?

      Current.family.accounts.find_by(id: id)
    end

    def linkable_accounts
      Current.family.accounts.visible.where(accountable_type: FUNDABLE_TYPES).alphabetically.to_a
    end
end
