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
      latitude = lat.to_f
      longitude = lng.to_f
      latitude_step = degrees_for_km(km)
      longitude_step = longitude_degrees_for_km(km, latitude)

      "#{(latitude / latitude_step).floor}:#{(longitude / longitude_step).floor}"
    end

    # Great-circle distance in km. A module method so non-model callers need no including class.
    def self.haversine(lat1, lng1, lat2, lng2)
      latitude_1 = deg_to_rad(lat1)
      latitude_2 = deg_to_rad(lat2)
      delta_latitude = deg_to_rad(lat2.to_f - lat1.to_f)
      delta_longitude = deg_to_rad(lng2.to_f - lng1.to_f)
      arc = Math.sin(delta_latitude / 2)**2 +
            Math.cos(latitude_1) * Math.cos(latitude_2) *
            Math.sin(delta_longitude / 2)**2

      EARTH_KM * 2 * Math.atan2(Math.sqrt(arc), Math.sqrt(1 - arc))
    end

    def self.deg_to_rad(value) = value.to_f * Math::PI / 180.0

    def self.degrees_for_km(km) = km.to_f / EARTH_KM * (180.0 / Math::PI)

    def self.longitude_degrees_for_km(km, latitude)
      degrees_for_km(km) / Math.cos(deg_to_rad([ latitude.to_f.abs, 0.0001 ].max))
    end

    # The rounded centre nearby searches from, or nil when GeoIsolation refuses
    # the coordinate. A module method, like cell_id, so it needs no model.
    def self.isolated_bounds_for(lat, lng)
      isolated = GeoIsolation.compute_isolated_bounds(latitude: lat, longitude: lng)
      isolated[:bounds] unless isolated[:status] == :error
    end

    class_methods do
      # Bbox-filtered nearby (fast, chainable like .nearby(lat, lng, 5).limit(20).includes(...) ).
      # For high precision on small result sets, post-filter with haversine or call .select.
      # Signature compatible with prior dupe scopes (positional km default).
      def nearby(lat, lng, km = 5)
        bounds = isolated_bounds_for(lat, lng)
        return none unless bounds

        center_lat, center_lng = bounds
        return none if center_lat == 0 && center_lng == 0

        d_lat = Shared::GeoLocatable.degrees_for_km(km)
        d_lng = Shared::GeoLocatable.longitude_degrees_for_km(km, center_lat)

        where(latitude: (center_lat - d_lat)..(center_lat + d_lat))
          .where(longitude: (center_lng - d_lng)..(center_lng + d_lng))
          .where.not(latitude: nil)
      end

      # Accurate haversine in km. Use for post-filter or distance checks.
      def haversine(lat1, lng1, lat2, lng2) = Shared::GeoLocatable.haversine(lat1, lng1, lat2, lng2)

      private

      def isolated_bounds_for(lat, lng) = Shared::GeoLocatable.isolated_bounds_for(lat, lng)
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
