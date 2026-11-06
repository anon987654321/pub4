# frozen_string_literal: true

# The deck's 20 km bounding box (Shared::GeoLocatable#nearby) filters
# dating_profiles on latitude and longitude on every home render and every
# swipe, and no index served the pair - the peer tables already carry the
# same shape (marketplace_listings, posts, takeaway_restaurants). city_id
# leads because every deck query is city-scoped first.
class AddCityAndCoordinatesIndexToDatingProfiles < ActiveRecord::Migration[8.2]
  def change
    add_index :dating_profiles, %i[city_id latitude longitude],
              name: "index_dating_profiles_on_city_id_and_latitude_and_longitude"
  end
end
