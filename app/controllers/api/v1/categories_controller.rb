# frozen_string_literal: true

# Lists the categories of the authenticated user's family.
#
# Added for mobile clients: a transaction form needs the full category list
# (with color, icon and parent) before the user picks one, and the transactions
# endpoint only embeds the category already attached to each transaction.
class Api::V1::CategoriesController < Api::V1::BaseController
  include Pagy::Backend

  CLASSIFICATIONS = %w[income expense].freeze

  before_action :ensure_read_scope

  def index
    family = current_resource_owner.family
    categories_query = family.categories.alphabetically

    if CLASSIFICATIONS.include?(params[:classification])
      categories_query = categories_query.where(classification: params[:classification])
    end

    @pagy, @categories = pagy(
      categories_query,
      page: safe_page_param,
      limit: safe_per_page_param
    )

    @per_page = safe_per_page_param

    render :index
  end

  private

    def ensure_read_scope
      authorize_scope!(:read)
    end

    def safe_page_param
      page = params[:page].to_i
      page > 0 ? page : 1
    end

    def safe_per_page_param
      per_page = params[:per_page].to_i

      # Default to 25, max 100 (same contract as the accounts endpoint)
      case per_page
      when 1..100
        per_page
      else
        25
      end
    end
end
