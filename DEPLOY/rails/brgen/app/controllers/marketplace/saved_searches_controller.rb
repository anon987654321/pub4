# frozen_string_literal: true

class Marketplace::SavedSearchesController < Marketplace::BaseController
  def index
    @saved_searches = Current.user.marketplace_saved_searches.order(created_at: :desc)
  end

  def create
    Current.user.marketplace_saved_searches.create!(saved_search_params)
    redirect_back fallback_location: marketplace_listings_path, notice: "Saved search"
  end

  def destroy
    Current.user.marketplace_saved_searches.find(params[:id]).destroy
    redirect_to marketplace_saved_searches_path, notice: "Deleted saved search"
  end

  private

  def saved_search_params
    params.require(:marketplace_saved_search).permit(:name, :query, :category_id, :location, :notify)
  end
end
