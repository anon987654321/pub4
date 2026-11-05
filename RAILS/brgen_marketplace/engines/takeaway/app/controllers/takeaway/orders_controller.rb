# frozen_string_literal: true

class Takeaway::OrdersController < Takeaway::BaseController
  # What can go wrong between us and Vipps when a payment starts.
  PAYMENT_ERRORS = [
    Marketplace::Payments::ProviderError, Net::OpenTimeout, Net::ReadTimeout, SocketError, JSON::ParserError, KeyError
  ].freeze

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
    @order = Takeaway::Order.new
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
    # restaurant: :user, because transition_to! names the kitchen's owner as the
    # activity actor, and a preloaded restaurant is strict about its own user.
    @order = Takeaway::Order.includes(restaurant: :user).find(params[:id])
    return mark_delivered_by_courier if !@order.restaurant.owner?(Current.user) && @order.carried_by?(Current.user)
    return cancel_by_diner if !@order.restaurant.owner?(Current.user) && @order.user_id == Current.user&.id

    if @order.restaurant.owner?(Current.user)
      target_status = params[:status].presence || @order.next_status
      # transition_to! refuses any step Takeaway::Order::TRANSITIONS does not
      # list, and says so rather than raising; the kitchen should see it too.
      unless @order.transition_to!(target_status)
        return redirect_to(order_path(@order), alert: @order.errors.full_messages.to_sentence)
      end
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

  # The courier can do one thing to an order: say it arrived. Any other step
  # stays the kitchen's.
  def mark_delivered_by_courier
    driver_page = delivery_driver_path(@order.delivery_driver_id)
    return redirect_to(driver_page, alert: @order.errors.full_messages.to_sentence) unless @order.deliver!

    redirect_to driver_page, notice: t("takeaway.marked_delivered", id: @order.id)
  end

  # Pays the diner's own order with Vipps. Nothing is charged here: the diner
  # approves in the Vipps app and the webhook records the payment.
  def pay
    @order = Current.user.takeaway_orders.includes(:restaurant).find(params[:id])
    return redirect_to(order_path(@order), alert: t("flash.takeaway.payment_unavailable")) unless @order.startable?

    url = Marketplace::Payments::VippsCheckout.start!(order: @order, return_url: order_url(@order))
    return redirect_to(order_path(@order), alert: t("flash.takeaway.payment_failed")) unless vipps_url?(url)

    redirect_to url, allow_other_host: true
  rescue Marketplace::Payments::NotConfigured
    redirect_to order_path(@order), alert: t("flash.takeaway.payment_unavailable")
  rescue *PAYMENT_ERRORS => error
    Rails.logger.warn("[takeaway] Vipps start for order #{@order.id}: #{error.class}: #{error.message}")
    redirect_to order_path(@order), alert: t("flash.takeaway.payment_failed")
  end

  # The diner can do one thing to their own order: call it off while the
  # kitchen has not yet confirmed it and nothing is paid. After that the food is
  # being made, or the money is with Vipps, and the restaurant decides.
  def cancel_by_diner
    unless params[:status] == "cancelled" && @order.cancellable_by_diner?(Current.user) && @order.cancel!
      return redirect_to(order_path(@order), alert: t("flash.takeaway.cancel_unavailable"))
    end

    @order.deliver_notification(@order.restaurant.user,
                                title: t("takeaway.diner_cancelled_title", id: @order.id),
                                body: t("takeaway.diner_cancelled_body", id: @order.id),
                                source: @order, kind: "order")
    redirect_to order_path(@order), notice: t("flash.takeaway.order_cancelled_by_diner")
  end

  private

  # Only Vipps' own hosts, over https: the URL comes back from Vipps' API.
  def vipps_url?(url)
    uri = URI.parse(url.to_s)
    uri.is_a?(URI::HTTPS) && uri.host.present? && (uri.host == "vipps.no" || uri.host.end_with?(".vipps.no"))
  rescue URI::InvalidURIError
    false
  end

  def set_restaurant = (@restaurant = find_by_slug_or_id(Takeaway::Restaurant, params[:restaurant_id]))
  # tip_cents and scheduled_for are the customer's, so they are permitted;
  # totals are recomputed server-side in calculate_totals! and never read from
  # the form.
  # The form sends the tip in kroner (tip_kroner); tip_cents stays permitted
  # for callers that already post it.
  def order_params
    params.require(:takeaway_order)
          .permit(:delivery_address, :special_instructions, :tip_kroner, :tip_cents, :scheduled_for)
  end
  def item_params = params.dig(:takeaway_order, :items) || {}
end
