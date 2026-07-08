# frozen_string_literal: true

require "test_helper"

class HealthControllerTest < ActionDispatch::IntegrationTest
  test "health returns status and dependency checks" do
    get "/health"

    assert_response :success
    body = JSON.parse(response.body)
    assert_includes %w[ok degraded], body["status"]
    assert body["checks"].key?("tts")
    assert body["checks"].key?("git")
  end

  test "rails health check is exempt from container warmup" do
    Rails.application.config.x.master_container = nil

    get "/up"

    assert_response :success
  end
end