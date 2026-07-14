# frozen_string_literal: true

# Read-only status endpoint for other local services on the same VPS (MASTER's
# chat agent) to query live tenant activity without a public API surface.
# Gated by a shared secret rather than user auth since callers aren't browsers.
class InternalController < ApplicationController
  allow_unauthenticated_access

  before_action :authenticate_internal_caller

  def status
    render json: {
      city: Current.city,
      generated_at: Time.now.utc.iso8601,
      marketplace_listings: Marketplace::Listing.count,
      takeaway_open_orders: Takeaway::Order.active.count,
      playlist_tracks: Playlist::Track.count,
      tv_live_streams: Tv::LiveStream.live.count,
      dating_profiles: Dating::Profile.count,
    }
  end

  private

  def authenticate_internal_caller
    expected = ENV["MASTER_INTERNAL_TOKEN"].to_s
    given = request.headers["X-Internal-Token"].to_s
    return head :unauthorized if expected.empty? || given.empty?
    return head :unauthorized unless ActiveSupport::SecurityUtils.secure_compare(expected, given)
  end
end
