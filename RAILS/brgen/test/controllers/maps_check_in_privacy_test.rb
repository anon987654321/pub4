# frozen_string_literal: true

require "test_helper"

# A place page is public. A name beside "5 minutes ago" tells anyone where
# that person stands, so the last hour's check-ins are counted, not named.
class MapsCheckInPrivacyTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    @place = Place.create!(city: @city, name: "Bryggen", kind: "attraction", latitude: 60.3974, longitude: 5.3244)
  end

  teardown { ActsAsTenant.current_tenant = nil }

  def check_in(name, checked_in_at:)
    user = User.strict_loading(false).create!(
      email_address: "checkin-#{SecureRandom.hex(4)}@brgen.no", password: "password123",
      username: "checkin_#{SecureRandom.hex(4)}", display_name: name, guest: false, city: @city
    )
    @place.place_check_ins.create!(user:, checked_in_at:)
  end

  test "a check-in from the last hour is counted, an older one named" do
    check_in("Nylig Person", checked_in_at: 5.minutes.ago)
    check_in("Tidligere Person", checked_in_at: 3.hours.ago)
    host! "maps.brgen.no"

    get maps.place_path(@place)

    assert_response :success
    assert_no_match "Nylig Person", response.body
    assert_match "Tidligere Person", response.body
    assert_match I18n.t("maps.checked_in_last_hour", count: 1), response.body
  end
end
