# frozen_string_literal: true

class HomeController < ApplicationController
  include Shared::LiveSearchable
  include Shared::MasterGuestHome

  def index
    return render_master_guest_home!(title: "Brgen") if params[:master].present? && master_guest_home?

    scope = if authenticated?
              Current.user.timeline_posts.hot
            elsif Brgen::DemoFeed.available?
              Brgen::DemoFeed.hot
            else
              Post.hot
            end
    scope = scope.includes(:user, :community, :votes)
    scope = apply_live_search(scope, columns: %w[title content], vertical: "feed") if live_search_query.present?
    @pagy, @posts = pagy(scope)
    @communities = Community.popular.limit(10)
    finish_live_search(partial: "home/live_search_results")
  end
end