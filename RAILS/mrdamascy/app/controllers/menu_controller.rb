# frozen_string_literal: true

class MenuController < ApplicationController
  # The catalog (root, APP_SPEC §6): kitchen hero facts, categories with
  # items + options eager-loaded, and the "Yalla igjen" reorder card when
  # the signed-in user has ordered before.
  def show
    @kitchen = Kitchen.first
    @categories = MenuCategory.includes(available_items: :item_options).ordered
    @last_order = current_user&.orders&.recent&.first
    @min_delivery_fee_ore = DeliveryZone.minimum(:fee_ore)
    @max_eta_minutes = DeliveryZone.maximum(:eta_minutes)
  end

  # One item with its options; the full-page sheet shares its markup with the
  # on-menu item sheet Stimulus behaviour (APP_SPEC §6/§8).
  def item
    @item = MenuItem.includes(:item_options).find(params[:id])
    @options = @item.item_options.ordered
  end
end
