# frozen_string_literal: true

module Marketplace
  class RankingService
    WEIGHTS = {
      relevance: 0.25,
      performance: 0.35,
      delivery: 0.20,
      seller: 0.20
    }.freeze

    # Persisted ranking is deliberately global and user-agnostic. A scheduled
    # recalculation has no buyer, so it must not depend on a user-local service
    # such as Amber's TasteRanker. Personalisation belongs in a request-layer
    # ranker that has an explicit preference source.
    def initialize(listing, query: nil)
      @listing = listing
      @query = query.to_s.downcase.strip
    end

    def score
      (
        relevance_score * WEIGHTS[:relevance] +
        performance_score * WEIGHTS[:performance] +
        delivery_score * WEIGHTS[:delivery] +
        seller_score * WEIGHTS[:seller]
      ).round(4)
    end

    def recalculate!
      value = score
      @listing.update_columns(ranking_score: value, updated_at: Time.current)
      value
    end

    private

    def relevance_score
      base = 0.4
      return base if @query.blank?

      title = @listing.title.to_s.downcase
      description = @listing.description.to_s.downcase
      category = @listing.category&.name.to_s.downcase

      score = base
      score += 0.35 if title.include?(@query)
      score += 0.15 if description.include?(@query)
      score += 0.10 if category.include?(@query)
      score.clamp(0.0, 1.0)
    end

    def performance_score
      events = @listing.events.recent(7)
      clicks = events.of_type("click").count
      carts = events.of_type("cart").count
      purchases = events.of_type("purchase").count
      returns = events.of_type("return").count

      return 0.15 if clicks.zero?

      conversion = purchases.to_f / clicks
      cart_rate = carts.to_f / clicks
      return_penalty = returns.positive? ? (1.0 - (returns.to_f / [purchases, 1].max)).clamp(0.0, 1.0) : 1.0

      ((conversion * 0.6) + (cart_rate * 0.4)).clamp(0.0, 1.0) * return_penalty
    end

    def delivery_score
      case @listing.delivery_promise
      when 0 then 1.00
      when 1 then 0.90
      when 2 then 0.75
      when 3 then 0.55
      when 4 then 0.30
      else 0.15
      end
    end

    def seller_score
      @listing.seller_score.to_f.clamp(0.0, 1.0)
    end
  end
end
