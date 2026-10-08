# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../app/services/shared/geo_isolation"

class SharedGeoIsolationTest < Minitest::Test
  def test_compute_isolated_bounds_rounds_coordinates
    result = Shared::GeoIsolation.compute_isolated_bounds(latitude: 59.9138688, longitude: 10.7522454)
    assert_equal :secure, result[:status]
    assert_equal [ 59.9139, 10.7522 ], result[:bounds]
  end

  def test_compute_isolated_bounds_rejects_non_hash
    result = Shared::GeoIsolation.compute_isolated_bounds("invalid")
    assert_equal :error, result[:status]
  end
end
