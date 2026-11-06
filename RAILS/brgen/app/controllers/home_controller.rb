# frozen_string_literal: true

class HomeController < ApplicationController
  include Shared::LiveSearchable
  include Shared::MasterGuestHome

  helper_method :newest_post_id, :hidden_author_ids

  def index
    return render_master_guest_home!(title: "Brgen") if params[:master].present? && master_guest_home?

    @local_activity = Brgen::LocalActivity.for(ActsAsTenant.current_tenant)
    @feed = params[:feed]
    scope = Brgen::HomeFeed.scope(feed: @feed, authenticated: authenticated?, sort: params[:sort])
    @neighborhoods = Neighborhood.in_city(ActsAsTenant.current_tenant)
    @neighborhood_id = @neighborhoods.where(id: chosen_neighborhood_id).pick(:id)
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

private

# The neighbourhood a reader picked stays picked on their next visit. A choice
# in the URL is remembered, an empty one forgets it, and a bare visit reads it
# back. Kept in the session, the one cookie the cookie page already declares.
def chosen_neighborhood_id
  return session[:home_neighborhood_id] unless params.key?(:neighborhood_id)

  session[:home_neighborhood_id] = params[:neighborhood_id].presence
end

  # The high-water mark a reconnecting front page catches up from: the feed is
  # ranked, so the newest post need not be among the cards on screen.
  def newest_post_id = Post.maximum(:id).to_i

  # People the reader has blocked, whose live cards feed_updates_controller
  # drops from the new-posts chip as HomeFeed drops their posts from the feed:
  # the city stream is rendered for nobody, so it cannot leave them out.
  def hidden_author_ids = Array(Current.user&.blocked_user_ids)
end
