# frozen_string_literal: true

module Brgen
  module HomeFeed
    # Posts between in-feed affiliate units. The reflex needs the same number
    # the first screen uses, and since amber renders the same unit now, so does
    # amber — so the number lives with the unit and this is the local name for
    # it rather than a second copy.
    AFFILIATE_EVERY = Shared::AffiliateHelper::FEED_EVERY

    module_function

    def following?(feed:)
      feed.to_s == "following"
    end

    def communities?(feed:)
      feed.to_s == "communities"
    end

    # BRGEN-104. The front page is newest-first, and hot is the named
    # alternative.
    #
    # It was the other way round: every branch here ordered by HOT_SQL and
    # newest-first existed only as `?sort=latest` reordering the result, so a
    # city feed that calls itself the city's now ranked by score and a post
    # could be hours old before it surfaced. Ranking is a thing a reader asks
    # for; freshness is what a feed is.
    #
    # `latest` is still accepted and still means fresh — it is what every
    # existing link says — so no URL anyone has bookmarked changes meaning.
    def scope(feed: nil, authenticated: false, user: Current.user, sort: nil)
      ranked = ranked?(sort:)
      base =
        if communities?(feed:) && authenticated
          user.community_feed
        elsif following?(feed:) && authenticated
          ranked ? user.timeline_posts.hot : user.timeline_posts.fresh
        elsif !authenticated && Brgen::DemoFeed.available?
          ranked ? Brgen::DemoFeed.hot : Brgen::DemoFeed.fresh
        else
          ranked ? Post.hot : Post.fresh
        end
      exclude_blocked(Post.visible_to(user).merge(base), user)
    end

    def ranked?(sort:)
      sort.to_s == "hot"
    end

    # A blocker never sees blocked users' posts in any feed.
    def exclude_blocked(relation, user)
      return relation unless user.respond_to?(:blocked_user_ids)

      ids = user.blocked_user_ids
      ids.any? ? relation.where.not(user_id: ids) : relation
    end
  end
end
