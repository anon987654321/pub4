# frozen_string_literal: true

module Brgen
  module HomeFeed
    # The sketch places the first sponsored unit after the second post: visible
    # enough to establish the commerce layer without turning the feed into an ad
    # rail. Keep the cadence local to Brgen; Amber keeps its own shared rhythm.
    AFFILIATE_EVERY = 2

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

    def media_only(relation)
      images = Post.where(id: relation.joins(:image_attachment).select(:id))
      videos = Post.where(id: relation.joins(:video_attachment).select(:id))
      relation.merge(images.or(videos)).distinct
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
