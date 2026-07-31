# frozen_string_literal: true

class LocationsController < ApplicationController
  ALERT_RADIUS_KM = NearbyController::DEFAULT_RADIUS_KM
  # Coarsen the stored/matched position to a ~1 km grid so an exact location
  # can't be triangulated from proximity pings — ample precision for a
  # "within N km" stranger feature, and much safer than storing raw GPS.
  LOCATION_PRECISION = 2

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
    me.update_columns(latitude: lat, longitude: lng, location_updated_at: Time.current)

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
      Shared::Pushable.push_to(other, title: "Someone nearby", body: "#{me.anon_handle} is within #{ALERT_RADIUS_KM.to_i} km — tap to chat", url: "/nearby")
    end

    head :ok
  end
end
