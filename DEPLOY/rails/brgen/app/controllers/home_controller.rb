# frozen_string_literal: true

class HomeController < ApplicationController
  include Shared::LiveSearchable

  def index
    scope = if authenticated?
              Current.user.timeline_posts.hot
            else
              Post.hot
            end
    scope = scope.includes(:user, :community, :votes)
    scope = apply_live_search(scope, columns: %w[title content], vertical: "feed") if live_search_query.present?
    @posts = scope.limit(live_search_query.present? ? 100 : 50)
    @communities = Community.popular.limit(10)
    finish_live_search(partial: "home/live_search_results")
  end
end