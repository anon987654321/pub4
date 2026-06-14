# frozen_string_literal: true

class Marketplace::OrdersController < Marketplace::BaseController
  before_action :set_listing

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
    @order = Marketplace::Order.find(params[:id])
    if @order.seller == Current.user
      @order.accept! if params[:accept]
      @order.decline! if params[:decline]
    end
    redirect_to marketplace_listing_path(@listing)
  end

  private

  def set_listing = (@listing = Marketplace::Listing.find(params[:listing_id]))
end
