# frozen_string_literal: true

require "test_helper"

# Search is open to guests and scans eight tables per request, so one address
# gets a bounded number of searches a minute.
class SearchRateLimitTest < ActionDispatch::IntegrationTest
  setup do
    Rails.cache.clear
    Brgen::CitySeed.sync! if City.table_exists?
    host! "brgen.no"
  end

  teardown { Rails.cache.clear }

  test "a guest past the per-minute ceiling is told to slow down" do
    SearchController::SEARCHES_PER_MINUTE.times { get global_search_path }
    assert_response :success

    get global_search_path(q: "bryggen")
    assert_response :too_many_requests

    travel 61.seconds do
      get global_search_path(q: "bryggen")
      assert_response :success
    end
  end
end
