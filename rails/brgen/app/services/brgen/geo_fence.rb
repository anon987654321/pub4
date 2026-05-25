# frozen_string_literal: true

module Brgen
  class GeoFence
    def self.inside?(lat, lng, polygon_coordinates)
      inside = false
      j = polygon_coordinates.size - 1
      polygon_coordinates.each_with_index do |poly, i|
        prev = polygon_coordinates[j]
        lng_spans = (poly[:lng] < lng && prev[:lng] >= lng) || (prev[:lng] < lng && poly[:lng] >= lng)
        if lng_spans
          lat_cross = poly[:lat] + (lng - poly[:lng]) / (prev[:lng] - poly[:lng]) * (prev[:lat] - poly[:lat])
          inside = !inside if lat_cross < lat
        end
        j = i
      end
      inside
    end
  end
end
