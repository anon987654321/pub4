# frozen_string_literal: true

require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  test "index renders the mission control shell" do
    get "/dashboard"

    assert_response :success
    assert_includes response.body, "mission control"
  end

  test "live requires authentication" do
    get "/dashboard/live"

    assert_response :unauthorized
  end

  test "live returns warming up when container absent" do
    Rails.application.config.x.master_container = nil

    get "/dashboard/live", headers: auth_headers, as: :json

    assert_response :service_unavailable
    assert_equal "warming up", JSON.parse(response.body)["error"]
  ensure
    Rails.application.config.x.master_container = stub_master_container
  end

  test "live returns the mission payload when container present" do
    get "/dashboard/live", headers: auth_headers

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "test/model", body["model"]
    assert body.key?("tokens")
    assert body.key?("open_breakers")
    assert body.key?("context_pressure")
    assert body.key?("provider_health")
    assert_equal "healthy", body.dig("provider_health", "status")
  end
end
