# frozen_string_literal: true

module Marketplace
  class RankingService
    WEIGHTS = {
      relevance: 0.25,
      performance: 0.35,
      delivery: 0.20,
      seller: 0.20
    }.freeze

    def initialize(listing, query: nil, user: nil)
      @listing = listing
      @query = query.to_s.downcase.strip
      @user = user
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
      score = (score * 0.7) + (taste_score * 0.3) if @user
      score.clamp(0.0, 1.0)
    end

    def taste_score
      return 0.5 unless defined?(TasteRanker) && TasteRanker.respond_to?(:score_for_listing)

      TasteRanker.score_for_listing(@user, listing_title: @listing.title, category: @listing.category&.name)
    rescue StandardError
      0.5
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
