# frozen_string_literal: true

class Takeaway::RestaurantsController < Takeaway::BaseController
  allow_unauthenticated_access only: %i[index show]
  before_action :set_restaurant, only: %i[show edit update destroy]

  def index
    scope = Takeaway::Restaurant.active.includes(:user)
    scope = scope.where(cuisine_type: params[:cuisine]) if params[:cuisine].present?
    scope = scope.where("name LIKE ?", "%#{params[:q]}%") if params[:q].present?
    @pagy, @restaurants = pagy(scope.popular)
  end

  def show
    @menu_items = @restaurant.menu_items.available
    @favorited = authenticated? && Current.user.takeaway_favorite_restaurants.exists?(restaurant: @restaurant)
    @reviews = load_neighbour_reviews
    @can_review = can_leave_review?
  end

  def new
    @restaurant = Takeaway::Restaurant.new
  end

  def create
    @restaurant = Current.user.takeaway_restaurants.build(restaurant_params)
    @restaurant.save ?
      redirect_to(takeaway_restaurant_path(@restaurant), notice: "Restaurant created") :
      render(:new, status: :unprocessable_entity)
  end

  def edit; end

  def update
    @restaurant.update(restaurant_params) ?
      redirect_to(takeaway_restaurant_path(@restaurant)) :
      render(:edit, status: :unprocessable_entity)
  end

  def destroy
    @restaurant.destroy
    redirect_to takeaway_restaurants_path
  end

  private

  def set_restaurant = (@restaurant = Takeaway::Restaurant.find(params[:id]))

  def restaurant_params = params.require(:takeaway_restaurant).permit(
    :name,
    :description,
    :address,
    :city,
    :phone,
    :cuisine_type,
    :delivery_fee_cents,
    :min_order_cents,
    :active,
  )

  def load_neighbour_reviews
    base = @restaurant.reviews.includes(:user).order(created_at: :desc).limit(12)
    return base unless authenticated? && Current.user&.latitude

    my_lat = Current.user.latitude.to_f
    my_lng = Current.user.longitude.to_f
    base.select do |r|
      rlat = r.reviewer_lat || r.user&.latitude
      rlng = r.reviewer_lng || r.user&.longitude
      next false unless rlat && rlng
      User.haversine(my_lat, my_lng, rlat.to_f, rlng.to_f) <= 4.0
    end
  end

  def can_leave_review?
    authenticated? && Current.user.takeaway_orders.where(restaurant: @restaurant, status: "delivered").exists?
  end
end
