# frozen_string_literal: true

class HomeController < ApplicationController
  def index
    scope = if authenticated?
              FeedRankingService.call(user: Current.user, scope: Current.user.timeline_posts.includes(:user, :community, :votes))
            else
              Post.hot.includes(:user, :community, :votes)
            end
    @pagy, @posts = pagy(scope)
    @communities = Community.popular.limit(10)
  end
end
