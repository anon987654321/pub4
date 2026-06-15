# frozen_string_literal: true
# AN624: Business discovery on MapLibre

module Maps
  class BusinessDiscovery
    def initialize(city:)
      @city = city
    end

    def clusters
      Place.where(city: @city).group_by { |p| [p.latitude.round(2), p.longitude.round(2)] }.map do |(lat, lng), places|
        { lat: lat, lng: lng, count: places.size, places: places.first(3) }
      end
    end
  end
end