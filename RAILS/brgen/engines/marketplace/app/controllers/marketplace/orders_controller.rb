# frozen_string_literal: true

class Marketplace::OrdersController < Marketplace::BaseController
  before_action :require_user_session
  before_action :set_listing, only: :create
  before_action :set_order, only: %i[show update]

  # Buyer's order history — a paid order used to vanish (the cart only lists
  # pending). Scoped to Current.user's own orders.
  def index
    @pagy, @orders = pagy(
      Marketplace::Order.where(buyer_id: Current.user.id)
                        .includes(:listing)
                        .order(created_at: :desc)
    )
  end

  def show
    authorize @order
    other = @order.buyer == Current.user ? @order.seller : @order.buyer
    @conversation = Conversation.find_or_create_direct(Current.user, other)
    @messages = @conversation.messages.visible.unexpired.order(:created_at)
    @message = Message.new
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
      @order.deliver_notification(@listing.user, title: "New marketplace offer", body: "#{Current.user.display_name} sent an offer for #{@listing.title}.", source: @order)
      @order.record_activity!("MarketplaceOfferSent", actor: Current.user, source_vertical: "marketplace", locality: @listing.location)
      redirect_to listing_path(@listing), notice: t("flash.marketplace.offer_sent")
    else
      redirect_to listing_path(@listing), alert: t("flash.marketplace.offer_failed")
    end
  end

  def update
    authorize @order
    if @order.seller == Current.user && @order.open_offer?
      @order.accept! if params[:accept]
      @order.decline! if params[:decline]
    end
    redirect_to order_path(@order)
  end

  private

  def set_listing = (@listing = find_by_slug_or_id(Marketplace::Listing.includes(:user), params[:listing_id]))

  def set_order = (@order = Marketplace::Order.includes(listing: :user, buyer: {}).find(params[:id]))
end
