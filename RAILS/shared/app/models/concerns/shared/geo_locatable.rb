# frozen_string_literal: true

# Geographic proximity shared by Brgen's marketplace, dating, and takeaway surfaces.
# Standardizes on pure-Ruby haversine + bbox prefilter for chainable scopes (no PostGIS/earthdistance dep).
# Replaces 5+ near-identical ad-hoc scopes with inconsistent math (euclid, deg approx, earth_distance, haversine).
# Usage:
#   include Shared::GeoLocatable
#   scope = Listing.nearby(lat, lng, 5)   # returns relation (bbox); for exact: .to_a.select { |l| Listing.haversine(...) <= 5 }
#   listing.geo? ; listing.distance_to(user_lat, user_lng)
module Shared
  module GeoLocatable
    extend ActiveSupport::Concern

    EARTH_KM = 6371.0

    included do
      # Models should have decimal latitude, longitude columns (or override lat/lng readers).
    end

    # Stable grid-cell id for "everyone roughly within `km` of each other" grouping
    # (e.g. a shared geo-scoped chat room) -- not for precise membership, since two
    # points on opposite sides of a cell edge can be `km` apart yet land in
    # different cells. Same lat-corrected bbox math as `nearby` below, just used
    # to bucket instead of to filter. Deterministic and pure Ruby (no geohash gem).
    # A module method (Shared::GeoLocatable.cell_id(...)), not `module_function` --
    # that would also privatize the plain instance methods below (geo?,
    # distance_to) for every including model, breaking their external callers.
    def self.cell_id(lat:, lng:, km: 10.0)
      d_lat = km / EARTH_KM * (180.0 / Math::PI)
      d_lng = d_lat / Math.cos([ lat.to_f.abs, 0.0001 ].max * Math::PI / 180.0)
      cell_lat = (lat.to_f / d_lat).floor
      cell_lng = (lng.to_f / d_lng).floor
      "#{cell_lat}:#{cell_lng}"
    end

    class_methods do
      # Bbox-filtered nearby (fast, chainable like .nearby(lat, lng, 5).limit(20).includes(...) ).
      # For high precision on small result sets, post-filter with haversine or call .select.
      # Signature compatible with prior dupe scopes (positional km default).
      def nearby(lat, lng, km = 5)
        isolated = GeoIsolation.compute_isolated_bounds(latitude: lat, longitude: lng)
        return none if isolated[:status] == :error

        lat, lng = isolated[:bounds]
        radius_km = km.to_f
        return none if lat == 0 && lng == 0

        d_lat = radius_km / EARTH_KM * (180.0 / Math::PI)
        d_lng = d_lat / Math.cos([ lat.abs, 0.0001 ].max * Math::PI / 180.0)

        where(latitude: (lat - d_lat)..(lat + d_lat))
          .where(longitude: (lng - d_lng)..(lng + d_lng))
          .where.not(latitude: nil)
      end

      # Accurate haversine in km. Use for post-filter or distance checks.
      def haversine(lat1, lng1, lat2, lng2)
        dlat = (lat2.to_f - lat1.to_f) * Math::PI / 180.0
        dlng = (lng2.to_f - lng1.to_f) * Math::PI / 180.0
        a = Math.sin(dlat / 2)**2 +
            Math.cos(lat1.to_f * Math::PI / 180.0) *
            Math.cos(lat2.to_f * Math::PI / 180.0) *
            Math.sin(dlng / 2)**2
        EARTH_KM * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
      end
    end

    def geo?
      latitude.present? && longitude.present?
    end

    def distance_to(other_lat, other_lng)
      return nil unless geo? && other_lat && other_lng
      self.class.haversine(latitude, longitude, other_lat, other_lng)
    end

    # Optional: simple geocode hook. Apps using geocoder gem can override.
    # For models with address column: after_validation :geocode_if_needed, if: :address_changed?
    def geocode!
      # No-op stub or integrate 'geocoder' gem + geocoded_by :address
      # Example override in Restaurant: geocoded_by :address; after_validation :geocode, if: :address_changed?
      Rails.logger&.debug("geocode! stub called for #{self.class}##{id}") if defined?(Rails)
      self
    end
  end
end
