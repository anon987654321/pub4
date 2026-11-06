# frozen_string_literal: true

class Marketplace::OrdersController < Marketplace::BaseController
  before_action :require_user_session
  before_action :set_listing, only: :create
  before_action :set_order, only: %i[show update capture ship deliver confirm_receipt]

  # Buyer's order history — a paid order used to vanish (the cart only lists
  # pending). Scoped to Current.user's own orders.
  def index
    return index_sales if params[:side] == "sales"

    @pagy, @orders = pagy(
      Marketplace::Order.where(buyer_id: Current.user.id)
                        .includes(listing: :category)
                        .order(created_at: :desc)
    )
  end

  def show
    authorize @order
    other = @order.buyer == Current.user ? @order.seller : @order.buyer
    @conversation = Conversation.find_or_create_direct(Current.user, other)
    @messages = @conversation.messages.visible.unexpired.order(:created_at)
    @message = Message.new
    @returns = @order.returns.includes(:resolved_by).order(created_at: :desc)
  end

  def create
    if @listing.expired? || @listing.status != "active"
      redirect_to listing_path(@listing), alert: t("flash.marketplace.offer_failed")
      return
    end

    quantity = params[:quantity].to_i.positive? ? params[:quantity].to_i : 1

    # The variant is what is bought when the listing has any, and its price is
    # the one to record — the listing's is the fallback for a listing with none.
    variant = @listing.variants.find_by(id: params.dig(:order, :variant_id))

    @order = @listing.orders.build(
      buyer: Current.user,
      message: params.dig(:order, :message),
      variant: variant,
      price_cents: variant&.price_cents_or_listing || @listing.price_cents,
      quantity: quantity
    )
    if @order.save
      @order.deliver_notification(
        @listing.user,
        title: I18n.t("marketplace.order_notification.new_offer"),
        body: I18n.t("marketplace.order_notification.new_offer_body", buyer: Current.user.display_name, title: @listing.title),
        source: @order,
        kind: "order"
      )
      @order.record_activity!("MarketplaceOfferSent", actor: Current.user, source_vertical: "marketplace", locality: @listing.location)
      @listing.record_event!("cart", user: Current.user, metadata: { order_id: @order.id, quantity: quantity })
      redirect_to listing_path(@listing), notice: t("flash.marketplace.offer_sent")
    else
      redirect_to listing_path(@listing), alert: t("flash.marketplace.offer_failed")
    end
  end

  def capture
    authorize @order
    unless @order.seller == Current.user && @order.payment_provider == "dintero" && @order.payment_status == "authorized"
      redirect_to order_path(@order), alert: t("flash.marketplace.capture_unavailable")
      return
    end

    Marketplace::Payments::DinteroCheckout.capture!(order: @order)
    redirect_to order_path(@order), notice: t("flash.marketplace.capture_started")
  rescue Marketplace::Payments::NotConfigured, Marketplace::Payments::ProviderError => error
    Rails.logger.warn("[dintero] capture order=#{@order.id}: #{error.class}: #{error.message}")
    redirect_to order_path(@order), alert: t("flash.marketplace.capture_failed")
  end

  def update
    authorize @order
    if @order.seller == Current.user && @order.open_offer?
      @order.accept! if params[:accept]
      @order.decline! if params[:decline]
    end
    redirect_to order_path(@order)
  end

  # The seller says the parcel has gone, with the carrier and tracking code the
  # buyer is sent. Sent again while it is on its way, it corrects them.
  def ship
    authorize @order, :update?
    return refuse_fulfilment unless @order.shippable?

    @order.ship!(carrier: params[:carrier].to_s.strip.first(60).presence,
                 tracking_code: params[:tracking_code].to_s.strip.first(100).presence)
    redirect_to order_path(@order), notice: t("flash.marketplace.order_shipped")
  end

  # The seller says it arrived. The buyer is asked to confirm; the shop's
  # payout waits for that, or for Order::RECEIPT_WINDOW without an answer.
  def deliver
    authorize @order, :update?
    return refuse_fulfilment unless @order.shippable?

    @order.report_delivered!
    redirect_to order_path(@order), notice: t("flash.marketplace.order_reported_delivered")
  end

  # The buyer confirms the parcel arrived, which is what releases the order to
  # the shop's payout queue.
  def confirm_receipt
    authorize @order, :confirm_receipt?
    return refuse_fulfilment unless @order.receipt_confirmable_by?(Current.user)

    @order.mark_delivered!
    redirect_to order_path(@order), notice: t("flash.marketplace.order_receipt_confirmed")
  end

  private

  def refuse_fulfilment = redirect_to(order_path(@order), alert: t("flash.marketplace.fulfilment_unavailable"))

  # The seller's list beside the buyer's: orders on their own listings,
  # filterable by status, with the pager rather than the buyer-only reflex.
  def index_sales
    @status = params[:status].presence_in(Marketplace::Sales::STATUSES)
    @pagy, @orders = pagy(Marketplace::Sales.for(Current.user, status: @status))
    render :sales
  end

  def set_listing = (@listing = find_by_slug_or_id(Marketplace::Listing.includes(:user), params[:listing_id]))

  def set_order = (@order = Marketplace::Order.includes(listing: %i[user store], buyer: {}).find(params[:id]))
end
