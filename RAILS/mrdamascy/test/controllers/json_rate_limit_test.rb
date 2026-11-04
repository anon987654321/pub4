# frozen_string_literal: true

require "test_helper"

# checkout#zone and orders#status answer JSON to scripts as readily as to
# the page; both are capped so neither can be hammered.
class JsonRateLimitTest < ActionDispatch::IntegrationTest
  test "the postcode lookup is capped per visitor" do
    60.times { get checkout_zone_path(postcode: "5004"), as: :json }
    assert_response :ok

    get checkout_zone_path(postcode: "5004"), as: :json
    assert_response :too_many_requests
  end

  test "the tracking poll is capped per order" do
    order = seed_order!(token: "tok-rate-1")
    30.times { get track_status_path(token: order.tracking_token), as: :json }
    assert_response :ok

    get track_status_path(token: order.tracking_token), as: :json
    assert_response :too_many_requests

    other = seed_order!(token: "tok-rate-2")
    get track_status_path(token: other.tracking_token), as: :json
    assert_response :ok
  end
end
