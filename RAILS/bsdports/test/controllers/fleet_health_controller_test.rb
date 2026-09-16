# frozen_string_literal: true

require "test_helper"

# /health is what relayd and the deploy read, so a false "unavailable" takes an
# app out of rotation over a database that was fine.
class FleetHealthControllerTest < ActionDispatch::IntegrationTest
  # An adapter that has not connected yet: active? is nil, a query still works.
  # It is the state of a worker between boot and its first request.
  class LazyConnection
    def active? = nil
    def select_value(_sql) = 1
  end

  # A store that accepts writes and keeps none.
  class ForgetfulCache
    def write(*) = true
    def read(*) = nil
  end

  def test_health_answers_ok_with_every_check_passing
    get "/health"

    assert_response :success
    # Solid Queue and Solid Cable have no tables in the test database, so the
    # two checks that read them answer false here and the status is degraded.
    assert_equal({ "database" => true, "cache" => true },
                 response.parsed_body.fetch("checks").slice("database", "cache"))
  end

  def test_a_database_not_yet_connected_is_still_available
    ActiveRecord::Base.stub(:connection, LazyConnection.new) { get "/health" }

    assert_response :success
    assert_equal true, response.parsed_body.dig("checks", "database")
  end

  def test_a_cache_that_keeps_no_write_reads_as_degraded
    Rails.stub(:cache, ForgetfulCache.new) { get "/health" }

    assert_equal false, response.parsed_body.dig("checks", "cache")
    assert_equal "degraded", response.parsed_body["status"]
  end
end
