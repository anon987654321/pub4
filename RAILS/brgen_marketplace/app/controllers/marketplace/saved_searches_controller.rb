# frozen_string_literal: true

class Marketplace::SavedSearchesController < Marketplace::BaseController
  # Every action reads Current.user's searches; without a reader the index
  # raised on nil and answered 500.
  before_action :require_user_session

  def index
    @pagy, @saved_searches = pagy(Current.user.marketplace_saved_searches.order(created_at: :desc))
  end

  # An invalid name is a message, not a 500 from create!.
  def create
    saved_search = Current.user.marketplace_saved_searches.new(saved_search_params)
    unless saved_search.save
      return redirect_back(fallback_location: listings_path, alert: saved_search.errors.full_messages.to_sentence)
    end

    saved_search.record_activity!("MarketplaceSearchSaved", actor: Current.user, source_vertical: "marketplace",
                                                            locality: saved_search.location, visibility: "private")
    redirect_back fallback_location: listings_path, notice: t("flash.marketplace.search_saved")
  end

  # Alerts on or off from the saved list, without saving the search again.
  def update
    saved_search = Current.user.marketplace_saved_searches.find(params[:id])
    saved_search.update!(notify: ActiveModel::Type::Boolean.new.cast(params[:notify]))
    redirect_to saved_searches_path,
                notice: t(saved_search.notify? ? "flash.marketplace.alerts_on" : "flash.marketplace.alerts_off")
  end

  def destroy
    Current.user.marketplace_saved_searches.find(params[:id]).destroy
    redirect_to saved_searches_path, notice: t("flash.marketplace.search_deleted")
  end

  private

  def saved_search_params
    params.require(:saved_search).permit(:name, :query, :category_id, :location, :notify)
  end
end
