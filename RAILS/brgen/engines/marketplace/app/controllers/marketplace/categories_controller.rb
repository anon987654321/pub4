# frozen_string_literal: true

class Marketplace::CategoriesController < Marketplace::BaseController
  allow_unauthenticated_access only: %i[show]

  def show
    @category = Marketplace::Category.find_by!(slug: params[:id])
    @pagy, @listings = pagy(@category.listings.live.recent)
  end
end
