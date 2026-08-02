# frozen_string_literal: true

class Marketplace::SavedSearchesController < Marketplace::BaseController
  def index
    @saved_searches = Current.user.marketplace_saved_searches.order(created_at: :desc)
  end

  def create
    saved_search = Current.user.marketplace_saved_searches.create!(saved_search_params)
    saved_search.record_activity!("MarketplaceSearchSaved", actor: Current.user, source_vertical: "marketplace", locality: saved_search.location, visibility: "private")
    redirect_back fallback_location: listings_path, notice: "Saved search"
  end

  def destroy
    Current.user.marketplace_saved_searches.find(params[:id]).destroy
    redirect_to saved_searches_path, notice: "Deleted saved search"
  end

  private

  def saved_search_params
    params.require(:marketplace_saved_search).permit(:name, :query, :category_id, :location, :notify)
  end
end
