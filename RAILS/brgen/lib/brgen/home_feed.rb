# frozen_string_literal: true

module Brgen
  module HomeFeed
    module_function

    def following?(feed:)
      feed.to_s == "following"
    end

    def scope(feed: nil, authenticated: false, user: Current.user)
      if following?(feed:) && authenticated
        user.timeline_posts.hot
      elsif !authenticated && Brgen::DemoFeed.available?
        Brgen::DemoFeed.hot
      else
        Post.hot
      end
    end
  end
end