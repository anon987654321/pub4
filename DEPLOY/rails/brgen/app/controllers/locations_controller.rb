# frozen_string_literal: true

class LocationsController < ApplicationController
  def update
    lat = params[:latitude].to_f
    lng = params[:longitude].to_f
    return head :bad_request unless lat.between?(-90, 90) && lng.between?(-180, 180)

    me = Current.user
    me.update_columns(latitude: lat, longitude: lng, location_updated_at: Time.current)

    # Broadcast to each nearby user that I just arrived/am still near.
    User.nearby(lat, lng).each do |other|
      next if other == me

      Turbo::StreamsChannel.broadcast_append_to(
        "nearby_alerts_#{other.id}",
        target: "nearby-alerts",
        partial: "nearby/alert",
        locals: { handle: me.anon_handle, user_id: me.id }
      )
      Shared::Pushable.push_to(other, title: "Someone nearby", body: "#{me.anon_handle} is within 2 km — tap to chat", url: "/nearby")
    end

    head :ok
  end
end
