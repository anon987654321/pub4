# frozen_string_literal: true

require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  # Through the key, not the English literal. This app serves nb by default, so
  # "mission control" is not what the page says — and a test that pins the
  # English spelling is a test that fails on a correct translation.
  test "index renders the mission control shell" do
    get "/dashboard"

    assert_response :success
    assert_includes response.body, I18n.t("dashboard.heading_mission")
  end

  test "index is Norwegian by default and English when the browser asks" do
    get "/dashboard"
    assert_includes response.body, 'lang="nb"'

    get "/dashboard", headers: { "HTTP_ACCEPT_LANGUAGE" => "en-GB,en;q=0.9" }
    assert_includes response.body, 'lang="en"'
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
