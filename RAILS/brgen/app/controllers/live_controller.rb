# frozen_string_literal: true

# Jodel-shaped hyperlocal Live layer: short anonymous posts ranked by local votes.
# Uses the same soft-guest identity as the rest of brgen — no signup to post.
class LiveController < ApplicationController
  rate_limit to: 20, within: 3.minutes, only: :create,
    with: -> { redirect_to live_path, alert: t("flash.live_rate_limited") }

  before_action :require_user_session, only: :create

  def index
    @radius_km = radius_km
    @sort = params[:sort].presence_in(%w[hot fresh]) || "hot"
    lat, lng = visitor_coords
    @located = lat.present? && lng.present?

    scope = Post.live.with_attached_image.includes(:user, :votes)
    if @located
      # Bbox prefilter then exact haversine — same pattern as marketplace/nearby.
      candidates = scope.nearby(lat, lng, @radius_km).to_a
      candidates.select! { |post| post.distance_to(lat, lng).to_f <= @radius_km }
      @posts = sort_posts(candidates)
      @pagy = nil
    else
      # City-tenant Live posts while waiting for GPS (browse without write).
      ranked = @sort == "fresh" ? scope.fresh : scope.hot
      @pagy, @posts = pagy(ranked)
    end
  end

  def create
    lat, lng = visitor_coords
    unless lat && lng
      redirect_to live_path, alert: t("flash.location_required_to_post")
      return
    end

    anon = Shared::AnonymousPost.new(request: request, user: Current.user)
    unless anon.allowed?
      redirect_to new_session_path, alert: t("flash.anonymous_post_limit", limit: Shared::AnonymousPost::LIMIT)
      return
    end

    body = live_content
    @post = Post.new(content: body, user: Current.user)
    @post.stamp_live_location!(lat: lat, lng: lng)
    @post.title = body.lines.first.to_s.strip.presence || body.strip
    @post.title = @post.title.truncate(300)

    unless PostModeration.new(@post).approve?
      redirect_to live_path, alert: t("flash.post_blocked_by_moderation")
      return
    end

    if @post.save
      anon.record_post!
      redirect_to live_path(sort: "fresh"), notice: t("flash.posted_to_live")
    else
      redirect_to live_path, alert: @post.errors.full_messages.to_sentence.presence || "Could not post."
    end
  end

  private

  def visitor_coords
    user = Current.user
    return [ nil, nil ] unless user&.latitude.present? && user.longitude.present?

    [ user.latitude.to_f, user.longitude.to_f ]
  end

  def radius_km
    value = params[:radius_km].presence || Post::LIVE_RADIUS_KM_DEFAULT
    value.to_f.clamp(0.5, Post::LIVE_RADIUS_KM_MAX)
  end

  def live_content
    params.require(:post).permit(:content)[:content].to_s.strip
  end

  def sort_posts(list)
    case @sort
    when "fresh"
      list.sort_by { |p| -p.created_at.to_i }
    else
      # Hot: vote sum desc, then fresher first. Use loaded association when present.
      list.sort_by do |p|
        score = p.votes.loaded? ? p.votes.sum { |v| v.value.to_i } : p.score
        [ -score, -p.created_at.to_i ]
      end
    end
  end
end
