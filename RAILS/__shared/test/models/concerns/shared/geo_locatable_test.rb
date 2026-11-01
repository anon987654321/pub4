# frozen_string_literal: true

require "minitest/autorun"
require "active_support"
require "active_support/concern"
require_relative "../../../../app/models/concerns/shared/geo_locatable"
require_relative "../../../../app/services/shared/geo_isolation"

class SharedGeoLocatableTest < Minitest::Test
  def test_haversine_one_degree_on_the_equator
    distance = Shared::GeoLocatable.haversine(0, 0, 0, 1)

    assert_in_delta 111.1949, distance, 0.0001
  end

  def test_haversine_is_symmetric
    forward = Shared::GeoLocatable.haversine(60.3913, 5.3221, 59.9139, 10.7522)
    reverse = Shared::GeoLocatable.haversine(59.9139, 10.7522, 60.3913, 5.3221)

    assert_in_delta forward, reverse, 0.0000001
  end

  def test_cell_id_is_stable_for_the_same_coordinate_and_radius
    coordinates = { lat: 60.3913, lng: 5.3221, km: 10.0 }

    assert_equal Shared::GeoLocatable.cell_id(**coordinates),
                 Shared::GeoLocatable.cell_id(**coordinates)
  end

  def test_isolated_bounds_for_uses_the_geo_isolation_rounding
    assert_equal [ 59.9139, 10.7522 ],
                 Shared::GeoLocatable.isolated_bounds_for(59.9138688, 10.7522454)
  end
end
