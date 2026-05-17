class LocationsController < ApplicationController
  def update
    lat = params[:latitude].to_f
    lng = params[:longitude].to_f
    return head :bad_request unless lat.between?(-90, 90) && lng.between?(-180, 180)

    Current.user.update_columns(latitude: lat, longitude: lng, location_updated_at: Time.current)
    head :ok
  end
end
