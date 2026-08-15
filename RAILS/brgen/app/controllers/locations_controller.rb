# frozen_string_literal: true

class LocationsController < ApplicationController
  rate_limit to: 30, within: 1.minute, only: :update, name: "geo_ping",
             by: -> { Current.user&.id ? "u#{Current.user.id}" : request.remote_ip }
  ALERT_RADIUS_KM = NearbyController::DEFAULT_RADIUS_KM
  # Coarsen the stored/matched position to a ~1 km grid so an exact location
  # can't be triangulated from proximity pings — ample precision for a
  # "within N km" stranger feature, and much safer than storing raw GPS.
  LOCATION_PRECISION = 2
  # How long a stationary user may go without re-announcing. Long enough that a
  # phone left on a desk stops broadcasting, short enough that someone who has
  # been sitting in a cafe is still findable.
  BROADCAST_COOLDOWN = 15.minutes

  def update
    # Soft guests are minted on every request; without a user there is nowhere
    # to store coordinates and nearby chat can never open.
    me = Current.user
    return head :unauthorized unless me

    lat = params[:latitude].to_f
    lng = params[:longitude].to_f
    return head :bad_request unless lat.between?(-90, 90) && lng.between?(-180, 180)

    lat = lat.round(LOCATION_PRECISION)
    lng = lng.round(LOCATION_PRECISION)

    # Re-announcing costs one rendered partial and one push lookup per nearby
    # user. Measured on production 2026-08-07: ~600 queries and 7-9s per call,
    # repeatedly, which is what took brgen.no off the air — clients ping on a
    # timer whether or not anyone has moved, and the position is already
    # coarsened to a ~1 km grid, so a stationary user re-broadcast the same
    # arrival every single ping.
    #
    # Announce on arrival in a new grid square, or once a cooldown has passed so
    # a long-stationary user is still discoverable. Otherwise record the position
    # and say nothing.
    moved = me.latitude&.round(LOCATION_PRECISION) != lat ||
            me.longitude&.round(LOCATION_PRECISION) != lng
    due = me.location_updated_at.nil? || me.location_updated_at < BROADCAST_COOLDOWN.ago

    me.update_columns(latitude: lat, longitude: lng, location_updated_at: Time.current)
    return head :ok unless moved || due

    # Broadcast to each nearby user that I just arrived/am still near.
    User.nearby(lat, lng, ALERT_RADIUS_KM).each do |other|
      next if other == me
      next if other.distance_to(lat, lng).to_f > ALERT_RADIUS_KM

      Turbo::StreamsChannel.broadcast_append_to(
        "nearby_alerts_#{other.id}",
        target: "nearby-alerts",
        partial: "nearby/alert",
        locals: { handle: me.anon_handle, user_id: me.id }
      )
      Shared::Pushable.push_to(other,
        title: t("nearby.push_title"),
        body: t("nearby.push_body", handle: me.anon_handle, km: ALERT_RADIUS_KM.to_i),
        url: "/nearby")
    end

    head :ok
  end
end
