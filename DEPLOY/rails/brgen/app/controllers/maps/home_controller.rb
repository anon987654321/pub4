# frozen_string_literal: true

module Maps
  class HomeController < BaseController
    allow_unauthenticated_access only: :index

    def index
      @mapbox_token = ENV.fetch("MAPBOX_API_KEY", "")
      @places_json = Place.includes(:city, :neighborhood).limit(500).map do |p|
        { id: p.id, name: p.name, kind: p.kind,
          lat: p.latitude, lng: p.longitude,
          city: p.city&.name, neighborhood: p.neighborhood&.name }
      end.to_json
    end
  end
end
