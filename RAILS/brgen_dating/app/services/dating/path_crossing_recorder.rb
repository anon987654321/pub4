# frozen_string_literal: true

class Dating::PathCrossingRecorder
  WINDOW = 5.minutes
  RADIUS_KM = 0.35

  def initialize(user:, profile:, latitude:, longitude:, now: Time.current)
    @user = user
    @profile = profile
    @latitude = latitude.to_f.round(3)
    @longitude = longitude.to_f.round(3)
    @now = now
  end

  def call
    return [] unless eligible?

    city_id = @profile.city_id || ActsAsTenant.current_tenant&.id
    return [] unless city_id

    Dating::LocationPing.where("expires_at <= ?", @now).delete_all
    Dating::PathCrossing.where("crossed_at < ?", @now - 14.days).delete_all

    ping = {
      city_id: city_id,
      user_id: @user.id,
      neighborhood_id: @profile.neighborhood_id,
      latitude: @latitude,
      longitude: @longitude,
      expires_at: @now + WINDOW,
      created_at: @now,
      updated_at: @now
    }
    Dating::LocationPing.upsert(
      ping,
      unique_by: :index_dating_location_pings_on_user_id
    )

    peers = nearby_pings(city_id)
    return [] if peers.empty?

    profiles = Dating::Profile.where(
      user_id: peers.map(&:user_id),
      visible: true,
      location_discovery_enabled: true
    ).where.not(verified_at: nil).index_by(&:user_id)
    return [] if profiles.empty?

    blocked_ids = blocked_user_ids(profiles.keys)
    peers.filter_map do |peer|
      next unless profiles.key?(peer.user_id)
      next if blocked_ids.include?(peer.user_id)
      next if distance_from(peer) > RADIUS_KM

      record_crossing(city_id, peer, profiles.fetch(peer.user_id))
    end
  end

  private

  def eligible?
    @profile &&
      @profile.user_id == @user.id &&
      @profile.visible? &&
      @profile.location_discovery_enabled? &&
      @profile.verified_at.present? &&
      @latitude.finite? &&
      @longitude.finite? &&
      (-90..90).cover?(@latitude) &&
      (-180..180).cover?(@longitude)
  end

  def nearby_pings(city_id)
    latitude_delta = RADIUS_KM / 110.574
    cosine = Math.cos(@latitude * Math::PI / 180).abs.clamp(0.01, 1.0)
    longitude_delta = RADIUS_KM / (111.320 * cosine)

    Dating::LocationPing.active(@now)
      .where(city_id: city_id)
      .where.not(user_id: @user.id)
      .where(latitude: (@latitude - latitude_delta)..(@latitude + latitude_delta))
      .where(longitude: (@longitude - longitude_delta)..(@longitude + longitude_delta))
  end

  def distance_from(peer)
    Shared::GeoLocatable.haversine(
      @latitude, @longitude, peer.latitude.to_f, peer.longitude.to_f
    )
  end

  def blocked_user_ids(peer_ids)
    return Set.new if peer_ids.empty?

    Block.where(blocker_id: @user.id, blocked_id: peer_ids)
         .or(Block.where(blocker_id: peer_ids, blocked_id: @user.id))
         .pluck(:blocker_id, :blocked_id)
         .flatten
         .to_set
         .subtract([@user.id])
  end

  def record_crossing(city_id, peer, peer_profile)
    user_a_id, user_b_id = [@user.id, peer.user_id].sort
    shared_neighborhood_id =
      @profile.neighborhood_id if @profile.neighborhood_id.present? &&
                                  @profile.neighborhood_id == peer_profile.neighborhood_id

    Dating::PathCrossing.find_or_create_by!(
      city_id: city_id,
      user_a_id: user_a_id,
      user_b_id: user_b_id,
      crossing_on: @now.to_date
    ) do |crossing|
      crossing.crossed_at = @now
      crossing.neighborhood_id = shared_neighborhood_id
      crossing.approx_latitude = ((@latitude + peer.latitude.to_f) / 2).round(2)
      crossing.approx_longitude = ((@longitude + peer.longitude.to_f) / 2).round(2)
    end
  rescue ActiveRecord::RecordNotUnique
    Dating::PathCrossing.find_by!(
      city_id: city_id,
      user_a_id: user_a_id,
      user_b_id: user_b_id,
      crossing_on: @now.to_date
    )
  end
end
