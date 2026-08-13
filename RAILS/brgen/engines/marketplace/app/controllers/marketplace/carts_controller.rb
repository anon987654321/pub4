# frozen_string_literal: true

class Marketplace::CartsController < Marketplace::BaseController
  before_action :require_user_session

  def show
    load_cart
  end

  # Re-notify sellers for every pending cart offer (batch "send all").
  # Offers are already created on add-to-cart; this is explicit bulk ping.
  def send_offers
    load_cart
    if @cart_items.empty?
      redirect_to cart_path, alert: t("flash.marketplace.cart_empty")
      return
    end

    sent = 0
    @cart_items.find_each do |order|
      next unless order.status == "pending"

      order.deliver_notification(
        order.seller,
        title: "Marketplace offer reminder",
        body: "#{Current.user.display_name} is waiting on an offer for #{order.listing.title}.",
        source: order
      )
      order.record_activity!(
        "MarketplaceOfferResent",
        actor: Current.user,
        source_vertical: "marketplace",
        locality: order.listing.location
      ) if order.respond_to?(:record_activity!)
      sent += 1
    end

    redirect_to cart_path,
                notice: t("flash.marketplace.offers_sent", count: sent)
  end

  private

  def load_cart
    @cart_items = Current.user.marketplace_orders
                         .where(status: "pending")
                         .includes(listing: :user)
                         .order(created_at: :desc)

    @cart_total = @cart_items.sum(&:total_cents)
    # Shown before the pay buttons, not discovered after the money has moved.
    @delivery_address = Current.user.marketplace_addresses.default_first.first
  end
end
