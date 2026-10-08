# frozen_string_literal: true

module Shared
  # Reading affiliate deals for a view, memoised for the request.
  #
  # Lifted out of brgen's ApplicationHelper with the rest of the affiliate stack,
  # so amber can render the same in-feed unit.
  #
  # The memo is not an optimisation detail, it is what makes the unit placeable.
  # The in-feed band renders once every HomeFeed::AFFILIATE_EVERY posts, so one
  # home feed asked Shared::Affiliate.deals six times for the same rows and
  # query_budget_test caught it at 21 queries against a ceiling of 20. The
  # sidebar unit asks a seventh time with a different limit. Keyed by the
  # arguments, so the units stay independent of one another without re-querying.
  module AffiliateHelper
    # Posts between in-feed units. Here rather than in a view because a view is
    # not the place to decide how often a reader is sold to, and here rather
    # than per app because two constants meaning the same rhythm is how the two
    # feeds drift apart. Brgen::HomeFeed::AFFILIATE_EVERY reads this.
    FEED_EVERY = 4

    def affiliate_deals_for(category: nil, limit: 8)
      @affiliate_deals_cache ||= {}
      @affiliate_deals_cache[[ category, limit ]] ||= Shared::Affiliate.deals(category:, limit:)
    end

    # Amazon's current Associates licence restricts Product Advertising Content
    # on sites intended for mobile use unless Amazon has granted written approval.
    # Amber and brgen are deliberately mobile-first, so the link survives but
    # Amazon-supplied title/image/price content stays out until the operator
    # records that approval explicitly.
    def affiliate_product_content_allowed?(deal)
      return true unless deal.respond_to?(:source) && deal.source.to_s == "amazon"

      ENV["AMAZON_PRODUCT_CONTENT_MOBILE_APPROVED"] == "1"
    end

    def affiliate_program_label(deal)
      return "Amazon Associates" if deal.respond_to?(:source) && deal.source.to_s == "amazon"

      "TradeDoubler"
    end
  end
end
