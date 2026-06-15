# frozen_string_literal: true
# AN615: Deal proximity via Haversine

module Marketplace
  class DealProximity
    EARTH_RADIUS_KM = 6371.0

    def self.near(lat:, lng:, scope: Deal.all, limit: 20)
      scope
        .select(Arel.sql("#{haversine_sql(lat, lng)} AS distance_km, marketplace_deals.*"))
        .order(Arel.sql("distance_km ASC, discount_percent DESC"))
        .limit(limit)
    end

    def self.haversine_sql(lat, lng)
      <<~SQL.squish
        (#{EARTH_RADIUS_KM} * acos(
          cos(radians(#{lat})) * cos(radians(latitude)) *
          cos(radians(longitude) - radians(#{lng})) +
          sin(radians(#{lat})) * sin(radians(latitude))
        ))
      SQL
    end
  end
end