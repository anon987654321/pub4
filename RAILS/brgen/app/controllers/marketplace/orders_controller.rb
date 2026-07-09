# frozen_string_literal: true

class Marketplace::OrdersController < Marketplace::BaseController
  before_action :require_user_session
  before_action :set_listing, only: :create
  before_action :set_order, only: %i[show update]

  def show
    authorize @order
    other = @order.buyer == Current.user ? @order.seller : @order.buyer
    @conversation = Conversation.find_or_create_direct(Current.user, other)
    @messages = @conversation.messages.order(:created_at)
    @message = Message.new
  end

  def create
    quantity = params[:quantity].to_i.positive? ? params[:quantity].to_i : 1

    @order = @listing.orders.build(
      buyer: Current.user,
      message: params.dig(:marketplace_order, :message),
      price_cents: @listing.price_cents,
      quantity: quantity
    )
    if @order.save
      Shared::Notifiable.deliver_notification(@listing.user, title: "New marketplace offer", body: "#{Current.user.display_name} sent an offer for #{@listing.title}.", source: @order)
      @order.record_activity!("MarketplaceOfferSent", actor: Current.user, source_vertical: "marketplace", locality: @listing.location)
      redirect_to marketplace_listing_path(@listing), notice: "Offer sent"
    else
      redirect_to marketplace_listing_path(@listing), alert: "Could not send offer"
    end
  end

  def update
    authorize @order
    if @order.seller == Current.user
      @order.accept! if params[:accept]
      @order.decline! if params[:decline]
    end
    redirect_to marketplace_order_path(@order)
  end

  private

  def set_listing = (@listing = Marketplace::Listing.find(params[:listing_id]))

  def set_order = (@order = Marketplace::Order.find(params[:id]))
end
