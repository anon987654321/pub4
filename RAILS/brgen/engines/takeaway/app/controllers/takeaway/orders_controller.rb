# frozen_string_literal: true

class Takeaway::OrdersController < Takeaway::BaseController
  # Guest checkout — no signup to place a takeaway order.
  before_action :require_user_session
  before_action :set_restaurant, only: %i[new create]

  def index
    @pagy, @orders = pagy(Current.user.takeaway_orders.recent.includes(:restaurant))
  end

  def show
    @order = Takeaway::Order.includes(:restaurant, order_items: :menu_item).find(params[:id])
    buyer = Current.user && @order.user_id == Current.user.id
    kitchen = @order.restaurant.owner?(Current.user)
    raise ActiveRecord::RecordNotFound unless buyer || kitchen
  end

  def new
    @order      = Takeaway::Order.new
    @menu_items = @restaurant.menu_items.available
  end

def create
  # A kitchen that is shut cannot cook now, but can take an order for later —
  # that is most of what scheduling is for. Checked here rather than only in
  # the view, because a hidden button is not a closing time.
  unless @restaurant.accepting_orders?(scheduled_for: order_params[:scheduled_for])
    redirect_to restaurant_path(@restaurant), alert: t("flash.takeaway.closed_now")
    return
  end

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

      redirect_to order_path(@order), notice: t("flash.takeaway.order_placed")
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
    redirect_to order_path(@order)
  end

  # Copies available items and the same address onto a new pending order.
  # Unavailable items are skipped; if none remain, send the diner to the
  # menu rather than placing an empty ticket.
  def again
    source = Current.user.takeaway_orders.includes(:restaurant, order_items: { menu_item: :restaurant }).find(params[:id])
    restaurant = source.restaurant
    unless restaurant.accepting_orders?
      redirect_to restaurant_path(restaurant), alert: t("flash.takeaway.closed_now")
      return
    end

    @order = source.build_reorder
    if @order.order_items.empty?
      redirect_to restaurant_path(restaurant), alert: t("flash.takeaway.reorder_empty")
      return
    end

    saved = ActiveRecord::Base.transaction do
      @order.save ? @order.calculate_totals! && true : false
    end
    if saved
      redirect_to order_path(@order), notice: t("flash.takeaway.order_placed")
    else
      redirect_to restaurant_path(restaurant), alert: @order.errors.full_messages.to_sentence
    end
  end

  private
  def set_restaurant = (@restaurant = find_by_slug_or_id(Takeaway::Restaurant, params[:restaurant_id]))
  # tip_cents and scheduled_for are the customer's, so they are permitted;
  # totals are recomputed server-side in calculate_totals! and never read from
  # the form.
  def order_params   = params.require(:takeaway_order).permit(:delivery_address, :special_instructions, :tip_cents, :scheduled_for)
  def item_params    = params.dig(:takeaway_order, :items) || {}
end
