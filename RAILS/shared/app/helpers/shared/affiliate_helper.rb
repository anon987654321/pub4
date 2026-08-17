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
      @affiliate_deals_cache[[ category, limit ]] ||= Shared::Affiliate.deals(category: category, limit: limit)
    end
  end
end
