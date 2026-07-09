# frozen_string_literal: true

class NearbyController < ApplicationController
  DEFAULT_RADIUS_KM = 2.0
  MAX_RADIUS_KM = 25.0

  def index
    lat = Current.user&.latitude
    lng = Current.user&.longitude
    @located = lat.present?
    @radius_km = radius_km
    @nearby = @located ? nearby_users(lat, lng, @radius_km) : []
  end

  def create
    other = User.find(params[:user_id])
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
