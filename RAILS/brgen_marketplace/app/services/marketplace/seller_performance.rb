# frozen_string_literal: true

class Marketplace::SellerPerformance
  WINDOW = 60.days
  EVENT_NAMES = {
    purchases: "MarketplacePurchaseCompleted",
    shipped: "MarketplaceOrderShipped",
    delivered: "MarketplaceOrderDelivered",
    returns: "MarketplaceReturnReceived",
  }.freeze

  def initialize(owner)
    @owner = owner
  end

  def summary(now: Time.current)
    listing_ids = listings.select(:id)
    events = ActivityEvent.where(
      subject_type: "Marketplace::Listing",
      subject_id: listing_ids,
      source_vertical: "marketplace",
      created_at: (now - WINDOW)..now,
      visibility: "private",
    )
    counts = events.group(:event_name).count
    review_scope = Marketplace::Review.where(listing_id: listing_ids)
    paid_sales = Marketplace::Order.joins(:listing)
      .where(listing_id: listing_ids, payment_status: "paid", paid_at: (now - WINDOW)..now)
      .group("marketplace_listings.currency")
      .sum(Arel.sql("COALESCE(marketplace_orders.price_cents, marketplace_listings.price_cents, 0) * marketplace_orders.quantity"))
    purchases = counts.fetch(EVENT_NAMES[:purchases], 0)
    shipped = counts.fetch(EVENT_NAMES[:shipped], 0)
    delivered = counts.fetch(EVENT_NAMES[:delivered], 0)
    returns = counts.fetch(EVENT_NAMES[:returns], 0)

    {
      purchases: purchases,
      shipped: shipped,
      delivered: delivered,
      returns: returns,
      delivery_completion_rate: ratio(delivered, shipped),
      return_rate: ratio(returns, purchases),
      paid_sales_by_currency: paid_sales,
      review_count: review_scope.count,
      average_rating: review_scope.average(:rating)&.to_f&.round(2),
    }
  end

  private

  def listings
    @listings ||= if @owner.is_a?(Marketplace::Store)
                    Marketplace::Listing.where(store_id: @owner.id)
                  else
                    Marketplace::Listing.where(user_id: @owner.id, store_id: nil)
                  end
  end

  def ratio(numerator, denominator)
    return nil if denominator.to_i.zero?

    (numerator.to_f / denominator).round(3)
  end
end
