# frozen_string_literal: true

class Takeaway::FavoriteRestaurantsController < Takeaway::BaseController
  before_action :require_user_session
  before_action :set_restaurant

  def create
    Current.user.takeaway_favorite_restaurants.find_or_create_by!(restaurant: @restaurant)
    redirect_back fallback_location: restaurant_path(@restaurant), notice: "Restaurant saved"
  end

  def destroy
    Current.user.takeaway_favorite_restaurants.find_by(restaurant: @restaurant)&.destroy
    redirect_back fallback_location: restaurant_path(@restaurant), notice: "Restaurant removed"
  end

  private

  def set_restaurant = (@restaurant = find_by_slug_or_id(Takeaway::Restaurant, params[:restaurant_id]))
end
