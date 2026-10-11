# frozen_string_literal: true

require "test_helper"

class Dating::PathCrossingRecorderTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    @first_user, @first_profile = make_verified_profile("crossing-a")
    @second_user, @second_profile = make_verified_profile("crossing-b")
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  def make_verified_profile(prefix)
    user = User.strict_loading(false).create!(
      email_address: "#{prefix}-#{SecureRandom.hex(3)}@brgen.no",
      password: "password123", city: @city
    )
    profile = Dating::Profile.new(
      user: user, age: 30, visible: true,
      location_discovery_enabled: true, verified_at: Time.current
    )
    attach_pixel!(profile.photos, filename: "#{prefix}.png")
    profile.save!
    [user, profile]
  end

  test "records an approximate crossing only for two visible verified opted-in profiles" do
    now = Time.zone.parse("2026-10-10 12:00:00")
    Dating::PathCrossingRecorder.new(
      user: @first_user, profile: @first_profile,
      latitude: 60.3921, longitude: 5.3225, now: now
    ).call

    crossings = Dating::PathCrossingRecorder.new(
      user: @second_user, profile: @second_profile,
      latitude: 60.3932, longitude: 5.3242, now: now + 30.seconds
    ).call

    assert_equal 1, crossings.size
    crossing = Dating::PathCrossing.last
    assert_equal @city.id, crossing.city_id
    assert_equal [@first_user.id, @second_user.id].sort, [crossing.user_a_id, crossing.user_b_id]
    assert_equal now.to_date, crossing.crossing_on
    assert_equal 60.39, crossing.approx_latitude.to_f
    assert_equal 5.32, crossing.approx_longitude.to_f
    assert_equal 0, Dating::LocationPing.active(now + 6.minutes).count
  end

  test "does not create a location ping when discovery consent is off" do
    @first_profile.update!(location_discovery_enabled: false)

    assert_no_difference "Dating::LocationPing.count" do
      Dating::PathCrossingRecorder.new(
        user: @first_user, profile: @first_profile,
        latitude: 60.3921, longitude: 5.3225
      ).call
    end
  end

  test "same-city pings expire and cannot create stale crossings" do
    now = Time.current
    Dating::LocationPing.create!(
      city: @city, user: @first_user, latitude: 60.392, longitude: 5.323,
      expires_at: now - 1.second
    )

    crossings = Dating::PathCrossingRecorder.new(
      user: @second_user, profile: @second_profile,
      latitude: 60.393, longitude: 5.324, now: now
    ).call

    assert_empty crossings
    assert_not Dating::LocationPing.exists?(user_id: @first_user.id)
  end
end
