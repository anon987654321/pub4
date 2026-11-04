# frozen_string_literal: true

module Marketplace
  # The buy bar's one-click order: same construction as OrdersController#create
  # (variant-aware price, quantity 1) minus the offer framing, because this is
  # a purchase rather than a negotiation. The seller still gets the order
  # notification. CheckoutsController#create hands the order to payment in the
  # same request.
  #
  # A double tap or a retry is the same purchase. Each click used to create
  # another order and tell the seller again; the buyer's unpaid order for this
  # listing and variant from the last few minutes is now paid instead, and one
  # already with the PSP is reported as in flight rather than started twice.
  class BuyNow
    REUSE_WINDOW = 10.minutes

    Outcome = Struct.new(:order, :listing, :refusal, :in_flight, keyword_init: true)

    def initialize(buyer:, listing_id:, variant_id:, provider:)
      @buyer = buyer
      @listing = Listing.includes(:store).find_by(id: listing_id)
      @variant_id = variant_id
      @provider = provider.to_s
    end

    def call
      refusal = refusal_reason
      return Outcome.new(listing: @listing, refusal:) if refusal

      variant = @listing.variants.find_by(id: @variant_id)
      recent = recent_order(variant)
      return Outcome.new(order: recent, listing: @listing, in_flight: !recent.startable?) if recent

      place(variant)
    end

    private

    def refusal_reason
      unbuyable = @listing.nil? || !@listing.buyable? || @listing.expired? || @listing.status != "active"
      return "flash.marketplace.offer_failed" if unbuyable

      dintero_unready = @provider == "dintero" && !Payments::DinteroCheckout.supported_listing?(@listing)
      return "flash.marketplace.dintero_seller_not_ready" if dintero_unready

      "flash.marketplace.offer_failed" if @listing.user_id == @buyer.id
    end

    def recent_order(variant)
      mine = @listing.orders.where(buyer_id: @buyer.id, variant:, quantity: 1)
      recent = mine.where(created_at: REUSE_WINDOW.ago.., payment_status: %w[unpaid pending failed])
      recent.order(:id).last
    end

    def place(variant)
      price_cents = variant&.price_cents_or_listing || @listing.price_cents
      order = @listing.orders.create(buyer: @buyer, variant:, price_cents:, quantity: 1)
      return Outcome.new(listing: @listing, refusal: "flash.marketplace.offer_failed") unless order.persisted?

      notify_seller(order)
      order.record_activity!("MarketplaceOfferSent", actor: @buyer, source_vertical: "marketplace")
      Outcome.new(order:, listing: @listing)
    end

    # By id, not listing.user: the listing arrives bare-loaded and
    # strict_loading raises on the lazy association, the same trap that hid
    # in ModerationWorkflow#penalize_owner.
    def notify_seller(order)
      seller = User.find_by(id: @listing.user_id)
      return unless seller

      title = I18n.t("marketplace.order_notification.new_order")
      body = I18n.t("marketplace.order_notification.new_order_body", buyer: @buyer.display_name, title: @listing.title)
      order.deliver_notification(seller, title:, body:, source: order, kind: "order")
    end
  end
end
