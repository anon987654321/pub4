# frozen_string_literal: true

class Takeaway::MenuItemsController < Takeaway::BaseController
  before_action :require_real_user
  before_action :set_restaurant

  def create
    @item = @restaurant.menu_items.build(item_params)
    @item.save ?
      redirect_to(restaurant_path(@restaurant), notice: t("flash.takeaway.menu_item_added")) :
      redirect_to(restaurant_path(@restaurant), alert: @item.errors.full_messages.to_sentence)
  end

  def destroy
    @restaurant.menu_items.find(params[:id]).destroy
    redirect_to restaurant_path(@restaurant)
  end

  private
  def set_restaurant = (@restaurant = find_by_slug_or_id(Current.user.takeaway_restaurants, params[:restaurant_id]))
  def item_params = params.require(:takeaway_menu_item).permit(:name, :description, :price_cents, :available, :vegetarian, :vegan, :photo)
end
