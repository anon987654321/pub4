# frozen_string_literal: true

module Maps
  class HomeController < BaseController
    allow_unauthenticated_access only: :index

    def index
      @mapbox_token = ENV.fetch("MAPBOX_API_KEY", "")
      city = Current.city_record
      @map_center_lat = city&.latitude.presence || 60.3913
      @map_center_lng = city&.longitude.presence || 5.3221
      places = Place.includes(:city, :neighborhood)
      places = places.where(city: city) if city
      @places_json = places.limit(500).map do |p|
        { id: p.id, name: p.name, kind: p.kind,
          lat: p.latitude, lng: p.longitude,
          city: p.city&.name, neighborhood: p.neighborhood&.name }
      end.to_json
    end
  end
end
