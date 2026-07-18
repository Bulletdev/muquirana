module AccountableResource
  extend ActiveSupport::Concern

  included do
    include Periodable

    before_action :set_account, only: [ :show, :edit, :update ]
    before_action :set_link_options, only: :new
  end

  class_methods do
    def permitted_accountable_attributes(*attrs)
      @permitted_accountable_attributes = attrs if attrs.any?
      @permitted_accountable_attributes ||= [ :id ]
    end
  end

  def new
    @account = Current.family.accounts.build(
      currency: Current.family.currency,
      accountable: accountable_type.new
    )
  end

  def show
    @chart_view = params[:chart_view] || "balance"
    @q = params.fetch(:q, {}).permit(:search)
    entries = @account.entries.search(@q).reverse_chronological

    @pagy, @entries = pagy(entries, limit: params[:per_page] || "10")
  end

  def edit
  end

  def create
    @account = Current.family.accounts.create_and_sync(account_params.except(:return_to))
    @account.lock_saved_attributes!

    redirect_to safe_return_to_path || @account, notice: t("accounts.create.success", type: accountable_type.name.underscore.humanize)
  end

  def update
    # Handle balance update if provided
    if account_params[:balance].present?
      result = @account.set_current_balance(account_params[:balance].to_d)
      unless result.success?
        @error_message = result.error_message
        render :edit, status: :unprocessable_entity
        return
      end
      @account.sync_later
    end

    # Update remaining account attributes
    update_params = account_params.except(:return_to, :balance, :currency)
    unless @account.update(update_params)
      @error_message = @account.errors.full_messages.join(", ")
      render :edit, status: :unprocessable_entity
      return
    end

    @account.lock_saved_attributes!
    redirect_back_or_to account_path(@account), notice: t("accounts.update.success", type: accountable_type.name.underscore.humanize)
  end

  private
    def set_link_options
      @show_us_link = Current.family.can_connect_plaid_us?
      @show_eu_link = Current.family.can_connect_plaid_eu?
    end

    def accountable_type
      controller_name.classify.constantize
    end

    # Only honor `return_to` when it is a same-site relative path. Left
    # unchecked, the user-controllable parameter is an open-redirect vector
    # (e.g. `https://evil.com`, `//evil.com`, or a `javascript:` URI). Anything
    # that is not a plain relative path is ignored, falling back to the account.
    def safe_return_to_path
      return_to = account_params[:return_to].to_s
      return if return_to.blank?
      return unless return_to.start_with?("/")
      return if return_to.start_with?("//", "/\\")

      return_to
    end

    def set_account
      @account = Current.family.accounts.find(params[:id])
    end

    def account_params
      params.require(:account).permit(
        :name, :balance, :subtype, :currency, :accountable_type, :return_to, :exclude_from_reports,
        accountable_attributes: self.class.permitted_accountable_attributes
      )
    end
end
