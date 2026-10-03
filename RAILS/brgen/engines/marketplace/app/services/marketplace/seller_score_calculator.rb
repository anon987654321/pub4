# frozen_string_literal: true

module Marketplace
  class SellerScoreCalculator
    WINDOW = 60.days

    def initialize(store_or_user)
      @owner = store_or_user
    end

    def score
      (
        on_time_rate * 0.35 +
        review_quality * 0.25 +
        low_return_rate * 0.20 +
        low_cancellation_rate * 0.20
      ).round(3).clamp(0.2, 1.0)
    end

    def apply!
      value = score
      if @owner.is_a?(Marketplace::Store)
        @owner.listings.live.update_all(seller_score: value, updated_at: Time.current)
      else
        Marketplace::Listing.where(user: @owner, store_id: nil).live
          .update_all(seller_score: value, updated_at: Time.current)
      end
      value
    end

    private

    def listings
      @listings ||= if @owner.is_a?(Marketplace::Store)
        @owner.listings
      else
        Marketplace::Listing.where(user: @owner, store_id: nil)
      end
    end

    def on_time_rate
      shipped = event_count("shipped", 60)
      delivered = event_count("delivered", 60)
      return 0.8 if shipped.zero?

      (delivered.to_f / shipped).clamp(0.0, 1.0)
    end

    def review_quality
      (listings.average(:rating).to_f / 5.0).clamp(0.0, 1.0)
    end

    def low_return_rate
      purchases = event_count("purchase", 60)
      returns = event_count("return", 60)
      return 0.9 if purchases.zero?

      1.0 - (returns.to_f / purchases).clamp(0.0, 1.0)
    end

    def low_cancellation_rate
      purchases = event_count("purchase", 60)
      cancelled = event_count("cancelled", 60)
      return 0.85 if purchases.zero?

      1.0 - (cancelled.to_f / purchases).clamp(0.0, 1.0)
    end

    def event_count(type, days)
      Marketplace::ListingEvent
        .joins(:listing)
        .where(marketplace_listings: { id: listings.select(:id) })
        .where(event_type: type)
        .where("marketplace_listing_events.occurred_at >= ?", days.days.ago)
        .count
    end
  end
end
