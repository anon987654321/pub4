class Marketplace::CategoriesController < Marketplace::BaseController
  allow_unauthenticated_access only: %i[show]

  def show
    @category = Marketplace::Category.find_by!(slug: params[:id])
    @pagy, @listings = pagy(@category.listings.active.recent)
  end
end
