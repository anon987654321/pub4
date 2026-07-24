# frozen_string_literal: true

class Takeaway::OrdersController < Takeaway::BaseController
  # Guest checkout — no signup to place a takeaway order.
  before_action :require_user_session
  before_action :set_restaurant, only: %i[new create]

  def index
    @pagy, @orders = pagy(Current.user.takeaway_orders.recent.includes(:restaurant))
  end

  def show
    @order = Current.user.takeaway_orders.includes(:restaurant, order_items: :menu_item).find(params[:id])
  end

  def new
    @order      = Takeaway::Order.new
    @menu_items = @restaurant.menu_items.available
  end

  def create
    @order = @restaurant.orders.build(order_params.merge(user: Current.user))
    item_params.each do |item_id, qty|
      next unless qty.to_i > 0
      item = @restaurant.menu_items.available.find_by(id: item_id)
      next unless item
      @order.order_items.build(menu_item: item, quantity: qty.to_i, unit_price_cents: item.price_cents)
    end
    saved = ActiveRecord::Base.transaction do
      @order.save ? @order.calculate_totals! && true : false
    end
    if saved

      redirect_to takeaway_order_path(@order), notice: "Order placed"
    else
      @menu_items = @restaurant.menu_items.available
      render :new, status: :unprocessable_entity
    end
  end

  def update
    @order = Takeaway::Order.includes(:restaurant).find(params[:id])
    if @order.restaurant.owner?(Current.user)
      target_status = params[:status].presence || @order.next_status
      @order.transition_to!(target_status)
    end
    redirect_to takeaway_order_path(@order)
  end

  private
  def set_restaurant = (@restaurant = Takeaway::Restaurant.find(params[:restaurant_id]))
  def order_params   = params.require(:takeaway_order).permit(:delivery_address, :special_instructions)
  def item_params    = params.dig(:takeaway_order, :items) || {}
end
