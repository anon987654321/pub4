# frozen_string_literal: true

require "zlib"

# A restaurant saved without coordinates got a pin anyway: its city's centre
# plus up to 0.01 degrees from a CRC of its address, city label and name. The
# model no longer does that, and this clears the pins it already wrote, since
# structured data published each one as where the restaurant is.
#
# A row is cleared only when its coordinates are exactly that arithmetic over
# its own fields and its own city, within the column's rounding, so a location
# an owner typed in is never touched. A row whose name, address or city label
# changed after the pin was written no longer reproduces it and keeps it, as
# does a pin anchored on a request's city rather than the row's.
class ClearSynthesizedTakeawayCoordinates < ActiveRecord::Migration[8.1]
  TOLERANCE = 0.000_001

  # Where the removed Takeaway::Restaurant#geocode! put a restaurant.
  def self.synthesized_pin(anchor_lat:, anchor_lng:, address:, city:, name:)
    seed = Zlib.crc32([ address, city, name ].join("|"))
    [
      anchor_lat.to_f + ((seed % 2_000) - 1_000) / 100_000.0,
      anchor_lng.to_f + (((seed / 2_000) % 2_000) - 1_000) / 100_000.0
    ]
  end

  def up
    select_rows(<<~SQL.squish).each { |row| clear_pin(row) if synthesized?(row) }
      SELECT r.id, r.latitude, r.longitude, r.address, r.city, r.name, c.latitude, c.longitude
        FROM takeaway_restaurants r
        JOIN cities c ON c.id = r.city_id OR (r.city_id IS NULL AND lower(c.name) = lower(r.city))
       WHERE r.latitude IS NOT NULL AND r.longitude IS NOT NULL
         AND c.latitude IS NOT NULL AND c.longitude IS NOT NULL
    SQL
  end

  # Nothing to restore: the pins were arithmetic, not locations.
  def down; end

  private

  def synthesized?(row)
    _id, lat, lng, address, city, name, anchor_lat, anchor_lng = row
    pin_lat, pin_lng = self.class.synthesized_pin(anchor_lat:, anchor_lng:, address:, city:, name:)
    (lat.to_f - pin_lat).abs < TOLERANCE && (lng.to_f - pin_lng).abs < TOLERANCE
  end

  def clear_pin(row)
    execute("UPDATE takeaway_restaurants SET latitude = NULL, longitude = NULL WHERE id = #{Integer(row.first)}")
  end
end
