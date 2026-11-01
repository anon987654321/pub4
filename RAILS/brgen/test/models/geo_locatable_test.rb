# frozen_string_literal: true

require "test_helper"

class GeoLocatableTest < ActiveSupport::TestCase
  test "haversine preserves Bergen to Oslo distance" do
    distance = Shared::GeoLocatable.haversine(60.3913, 5.3221, 59.9139, 10.7522)

    assert_in_delta 305.0667, distance, 0.0001
  end

  test "cell identifiers preserve the established latitude-corrected grid" do
    assert_equal "671:29", Shared::GeoLocatable.cell_id(lat: 60.3913, lng: 5.3221, km: 10)
  end
end
