# frozen_string_literal: true

class Marketplace::OrdersController < Marketplace::BaseController
  before_action :set_listing

  def create
    @order = @listing.orders.build(buyer: Current.user,
                                   message: params.dig(:marketplace_order, :message),
                                   price_cents: @listing.price_cents)
    if @order.save
      notify_seller!
      record_offer_activity!
      redirect_to marketplace_listing_path(@listing), notice: "Offer sent"
    else
      redirect_to marketplace_listing_path(@listing), alert: "Could not send offer"
    end
  end

  def update
    @order = Marketplace::Order.find(params[:id])
    if @order.seller == Current.user
      @order.accept! if params[:accept]
      @order.decline! if params[:decline]
    end
    redirect_to marketplace_listing_path(@listing)
  end

  private

  def set_listing = (@listing = Marketplace::Listing.find(params[:listing_id]))

  def notify_seller!
    return unless defined?(Notification)

    @listing.user.notifications.create!(
      title: "New marketplace offer",
      body: "#{Current.user.display_name} sent an offer for #{@listing.title}.",
      source_type: @order.class.name,
      source_id: @order.id
    )
  end

  def record_offer_activity!
    return unless defined?(ActivityEventRecorder)

    ActivityEventRecorder.call(
      actor: Current.user,
      event_name: "MarketplaceOfferSent",
      object: @order,
      source_vertical: "marketplace",
      locality: @listing.location
    )
  end
end
