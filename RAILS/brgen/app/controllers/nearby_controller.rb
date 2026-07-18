# frozen_string_literal: true

class NearbyController < ApplicationController
  DEFAULT_RADIUS_KM = 10.0
  MAX_RADIUS_KM = 25.0

  # Anonymous stranger chat is abuse-prone — cap how fast conversations start.
  rate_limit to: 15, within: 5.minutes, only: %i[create],
    with: -> { redirect_to nearby_path, alert: "Slow down — too many chats started. Try again shortly." }

  def index
    lat = Current.user&.latitude
    lng = Current.user&.longitude
    @located = lat.present?
    @radius_km = radius_km
    @nearby = @located ? nearby_users(lat, lng, @radius_km) : []
  end

  def create
    other = User.find(params[:user_id])
    return redirect_to(nearby_path, alert: "That's you.") if other == Current.user

    # Only start chats with people actually in range — don't let the endpoint
    # open a DM to an arbitrary user id (enumeration / non-consensual contact).
    lat = Current.user&.latitude
    lng = Current.user&.longitude
    in_range = lat && lng && other.distance_to(lat, lng).to_f <= MAX_RADIUS_KM
    return redirect_to(nearby_path, alert: "That person isn't nearby anymore.") unless in_range

    conversation = Conversation.find_or_create_direct(Current.user, other)
    redirect_to conversation
  end

  private

  def radius_km
    value = params[:radius_km].presence || DEFAULT_RADIUS_KM
    value.to_f.clamp(0.5, MAX_RADIUS_KM)
  end

  def nearby_users(lat, lng, radius)
    User.nearby(lat, lng, radius).reject { |user| user == Current.user }.filter_map do |user|
      distance = user.distance_to(lat, lng)
      next if distance.nil? || distance > radius

      [ user, distance ]
    end.sort_by(&:last)
  end
end
