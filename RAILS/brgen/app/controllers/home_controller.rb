# frozen_string_literal: true

class HomeController < ApplicationController
  include Shared::LiveSearchable
  include Shared::MasterGuestHome

  def index
    return render_master_guest_home!(title: "Brgen") if params[:master].present? && master_guest_home?

    @local_activity = Brgen::LocalActivity.for(ActsAsTenant.current_tenant)
    @feed = params[:feed]
    scope = Brgen::HomeFeed.scope(feed: @feed, authenticated: authenticated?, sort: params[:sort])
    @neighborhoods = Neighborhood.where(city_id: ActsAsTenant.current_tenant&.id).order(:name)
    @neighborhood_id = @neighborhoods.where(id: params[:neighborhood_id]).pick(:id)
    scope = scope.where(neighborhood_id: @neighborhood_id) if @neighborhood_id
    scope = Brgen::HomeFeed.media_only(scope) if params[:view].to_s == "media"
    # with_attached_image, or the card's `post.image.attached?` costs one
    # active_storage_attachments query per post — 25 on a full page.
    scope = scope.includes(:user, :community, :votes).with_attached_image.with_attached_images
    scope = scope.with_attached_video if params[:view].to_s == "media"
    scope = apply_live_search(scope, columns: %w[title content], vertical: "feed") if live_search_query.present?
    @pagy, @posts = pagy(scope)
    @communities = Community.popular_cached(limit: 10)
    finish_live_search(partial: "home/live_search_results")
  end
end
