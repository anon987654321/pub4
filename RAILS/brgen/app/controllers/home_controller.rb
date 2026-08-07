# frozen_string_literal: true

class HomeController < ApplicationController
  include Shared::LiveSearchable
  include Shared::MasterGuestHome

  def index
    return render_master_guest_home!(title: "Brgen") if params[:master].present? && master_guest_home?

    @feed = params[:feed]
    scope = Brgen::HomeFeed.scope(feed: @feed, authenticated: authenticated?)
    scope = scope.reorder(created_at: :desc) if params[:sort] == "latest"
    # with_attached_image, or the card's `post.image.attached?` costs one
    # active_storage_attachments query per post — 25 on a full page.
    scope = scope.includes(:user, :community, :votes).with_attached_image
    scope = apply_live_search(scope, columns: %w[title content], vertical: "feed") if live_search_query.present?
    @pagy, @posts = pagy(scope)
    @communities = Community.popular_cached(limit: 10)
    finish_live_search(partial: "home/live_search_results")
  end
end
