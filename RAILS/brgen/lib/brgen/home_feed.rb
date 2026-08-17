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

    def scope(feed: nil, authenticated: false, user: Current.user)
      base =
        if communities?(feed:) && authenticated
          user.community_feed
        elsif following?(feed:) && authenticated
          user.timeline_posts.hot
        elsif !authenticated && Brgen::DemoFeed.available?
          Brgen::DemoFeed.hot
        else
          Post.hot
        end
      exclude_blocked(Post.visible_to(user).merge(base), user)
    end

    # A blocker never sees blocked users' posts in any feed.
    def exclude_blocked(relation, user)
      return relation unless user.respond_to?(:blocked_user_ids)

      ids = user.blocked_user_ids
      ids.any? ? relation.where.not(user_id: ids) : relation
    end
  end
end
