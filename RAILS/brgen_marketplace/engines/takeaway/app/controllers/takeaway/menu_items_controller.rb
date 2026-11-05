# frozen_string_literal: true

class Takeaway::MenuItemsController < Takeaway::BaseController
  before_action :require_real_user
  before_action :set_restaurant

  def create
    attributes = item_params.to_h.symbolize_keys
    attributes[:allergens] = Takeaway::MenuItem.allergens_from(params.fetch(:takeaway_menu_item, {}))
    category_name = attributes.delete(:menu_category_name).to_s.strip
    @item = @restaurant.menu_items.build(attributes)

    saved = ActiveRecord::Base.transaction do
      if category_name.present?
        category = menu_category_named(category_name)
        unless category.save
          @item.errors.add(:base, category.errors.full_messages.to_sentence)
          raise ActiveRecord::Rollback
        end
        @item.menu_category = category
      end
      raise ActiveRecord::Rollback unless @item.save

      true
    end

    saved ?
      redirect_to(restaurant_path(@restaurant), notice: t("flash.takeaway.menu_item_added")) :
      redirect_to(restaurant_path(@restaurant), alert: @item.errors.full_messages.to_sentence)
  end

  # The kitchen states (or corrects) what a dish contains.
  def update
    item = @restaurant.menu_items.find(params[:id])
    if item.update(allergens: Takeaway::MenuItem.allergens_from(params.fetch(:takeaway_menu_item, {})))
      redirect_to restaurant_path(@restaurant, anchor: "menu"), notice: t("flash.takeaway.allergens_saved")
    else
      problems = item.errors.full_messages
      redirect_to restaurant_path(@restaurant, anchor: "menu"), alert: problems.to_sentence
    end
  end

  def destroy
    @restaurant.menu_items.find(params[:id]).destroy
    redirect_to restaurant_path(@restaurant)
  end

  private

  # Case-insensitive, so "middag" lands in "Middag". A new section takes the
  # typed name: first_or_initialize cannot copy it out of the string condition.
  def menu_category_named(name)
    same_name = @restaurant.menu_categories.where("LOWER(name) = ?", name.downcase)
    same_name.first_or_initialize(name:)
  end

  def set_restaurant = (@restaurant = find_by_slug_or_id(Current.user.takeaway_restaurants, params[:restaurant_id]))
  def item_params = params.require(:takeaway_menu_item).permit(:name, :description, :price_cents, :available, :vegetarian, :vegan, :photo, :menu_category_name)
end
