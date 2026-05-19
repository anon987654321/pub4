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
  def set_restaurant    = (@restaurant = Takeaway::Restaurant.find(params[:id]))
  def restaurant_params = params.require(:takeaway_restaurant).permit(
    :name, :description, :address, :city, :phone, :cuisine_type,
    :delivery_fee_cents, :min_order_cents, :active
  )
end
