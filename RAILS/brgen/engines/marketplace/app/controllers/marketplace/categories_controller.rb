# frozen_string_literal: true

class Marketplace::CategoriesController < Marketplace::BaseController
  allow_unauthenticated_access only: %i[show]

  def show
    @category = Marketplace::Category.includes(:parent, :children).find_by!(slug: params[:id])
    @sort = Marketplace::Listing::SORTS.include?(params[:sort]) ? params[:sort] : "recent"
    scope = @category.listings.live.with_attached_photos.includes(:user, :category)
    @pagy, @listings = pagy(scope.sorted_by(@sort))
    # A leaf category offers its siblings, so the shortcut row is never the
    # page pointing at itself alone.
    @shortcuts = @category.children.presence ||
                 (@category.parent_id ? Marketplace::Category.where(parent_id: @category.parent_id).order(:name).to_a : [])
  end
end
