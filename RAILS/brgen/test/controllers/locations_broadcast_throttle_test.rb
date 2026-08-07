# frozen_string_literal: true

require "test_helper"

# LocationsController#update announced arrival to every nearby user on every
# ping — one rendered partial and one push lookup each. Measured on production
# 2026-08-07: ~600 queries and 7-9 seconds per call, arriving continuously, which
# is what took brgen.no off the air.
#
# Clients ping on a timer whether or not anyone moved, and the stored position is
# coarsened to a ~1 km grid, so a stationary user re-announced the identical
# arrival every time. Announce on entering a new grid square, or once the
# cooldown has elapsed; otherwise record the position silently.
class LocationsBroadcastThrottleTest < ActionDispatch::IntegrationTest
  setup do
    host! "brgen.no"
    Brgen::CitySeed.sync! if City.table_exists?
    @user = User.strict_loading(false).create!(
      email_address: "pinger@brgen.no", password: "password123", username: "pinger", guest: false
    )
    post session_path, params: { email_address: @user.email_address, password: "password123" }
    @user.update_columns(latitude: nil, longitude: nil, location_updated_at: nil)
  end

  def ping(lat:, lng:)
    patch location_path, params: { latitude: lat, longitude: lng },
                         headers: { "ACCEPT" => "application/json" }
  end

# Counting queries, not broadcasts. The production symptom was ~600 queries per
# call: one rendered partial and one push lookup per nearby user. A subscriber
# on broadcast.action_cable reported zero either way, which made the first
# version of this test pass whether or not the throttle existed.
def queries_during
  count = 0
  counter = ->(_n, _s, _f, _i, payload) do
    count += 1 unless payload[:name].to_s.in?(%w[SCHEMA TRANSACTION CACHE])
  end
  ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { yield }
  count
end

  test "a repeat ping from the same grid square does not re-announce" do
    ping(lat: 60.39, lng: 5.32)
    assert_response :success

    first = queries_during { ping(lat: 60.40, lng: 5.33) }
    repeat = queries_during { ping(lat: 60.40, lng: 5.33) }
    assert_response :success
    assert_operator repeat, :<, first,
                    "a stationary repeat ping cost #{repeat} queries against #{first} for the " \
                    "announcing ping — the broadcast loop is still running on every ping"
  end

  # Sub-grid jitter is the common case: GPS wobbles by metres while the phone
  # sits still, and rounding to LOCATION_PRECISION is what makes that a no-op.
  test "jitter within the same grid square does not re-announce" do
    ping(lat: 60.39, lng: 5.32)
    moved = queries_during { ping(lat: 60.42, lng: 5.36) }
    jitter = queries_during { ping(lat: 60.4201, lng: 5.3599) }

    assert_operator jitter, :<, moved,
                    "GPS jitter inside one grid square cost #{jitter} queries against #{moved} " \
                    "for a real move — rounding to LOCATION_PRECISION is not throttling"
  end

  test "the position is still recorded on every ping" do
    ping(lat: 60.39, lng: 5.32)
    first = @user.reload.location_updated_at
    assert_not_nil first

    ping(lat: 60.39, lng: 5.32)
    assert_operator @user.reload.location_updated_at, :>=, first,
                    "a throttled ping must still record that the user is present"
  end

  test "moving to a new grid square announces again" do
    ping(lat: 60.39, lng: 5.32)
    @user.reload
    assert_equal 60.39, @user.latitude.to_f.round(2)

    ping(lat: 60.42, lng: 5.35)
    assert_response :success
    assert_equal 60.42, @user.reload.latitude.to_f.round(2),
                 "a real move must be stored so nearby matching sees the new square"
  end
end
