# frozen_string_literal: true

require "test_helper"

# A place is a point on the map; one that cannot be drawn is refused at save.
class PlaceTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
  end

  teardown { ActsAsTenant.current_tenant = nil }

  def place(latitude:, longitude:)
    Place.new(city: @city, name: "Bryggen", kind: "attraction", latitude:, longitude:)
  end

  test "a coordinate on the globe is accepted" do
    assert place(latitude: 60.3974, longitude: 5.3244).valid?
    assert place(latitude: -90, longitude: 180).valid?
  end

  test "an out-of-range latitude or longitude is refused" do
    assert_not place(latitude: 90.5, longitude: 5.32).valid?
    assert_not place(latitude: -91, longitude: 5.32).valid?
    assert_not place(latitude: 60.39, longitude: 180.1).valid?
    assert_not place(latitude: 60.39, longitude: -200).valid?
  end
end
