# frozen_string_literal: true

class Marketplace::OrdersController < Marketplace::BaseController
  before_action :set_listing

  def create
    @order = @listing.orders.build(buyer: Current.user,
                                   message: params.dig(:marketplace_order, :message),
                                   price_cents: @listing.price_cents)
    @order.save ?
      redirect_to(marketplace_listing_path(@listing), notice: "Offer sent") :
      redirect_to(marketplace_listing_path(@listing), alert: "Could not send offer")
  end

  def update
    @order = Marketplace::Order.find(params[:id])
    if @order.seller == Current.user
      @order.accept!   if params[:accept]
      @order.decline!  if params[:decline]
    end
    redirect_to marketplace_listing_path(@listing)
  end

  private
  def set_listing = (@listing = Marketplace::Listing.find(params[:listing_id]))
end
