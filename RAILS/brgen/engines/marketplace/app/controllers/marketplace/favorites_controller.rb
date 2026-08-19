# frozen_string_literal: true

class Marketplace::FavoritesController < Marketplace::BaseController
  before_action :require_user_session
  before_action :set_listing, except: :index

  # The saved list itself. Saving had a button on every card and nowhere to see
  # what you had saved, so the star was write-only.
  def index
    @pagy, @listings = pagy(
      Marketplace::Listing.where(id: Marketplace::ListingFavorite.where(user_id: Current.user.id).select(:listing_id))
                          .live.with_attached_photos.includes(:user, :category).recent
    )
  end

  def create
    @listing.favorites.find_or_create_by!(user: Current.user)
    redirect_back fallback_location: listing_path(@listing), notice: t("flash.marketplace.listing_saved")
  end

  def destroy
    @listing.favorites.find_by(user: Current.user)&.destroy
    redirect_back fallback_location: listing_path(@listing), notice: t("flash.marketplace.listing_unsaved")
  end

  private

  def set_listing = (@listing = find_by_slug_or_id(Marketplace::Listing, params[:listing_id]))
end
