# frozen_string_literal: true

class Marketplace::FavoritesController < Marketplace::BaseController
  before_action :require_user_session
  before_action :set_listing

  def create
    @listing.favorites.find_or_create_by!(user: Current.user)
    redirect_back fallback_location: listing_path(@listing), notice: "Saved listing"
  end

  def destroy
    @listing.favorites.find_by(user: Current.user)&.destroy
    redirect_back fallback_location: listing_path(@listing), notice: "Removed saved listing"
  end

  private

  def set_listing = (@listing = find_by_slug_or_id(Marketplace::Listing, params[:listing_id]))
end
