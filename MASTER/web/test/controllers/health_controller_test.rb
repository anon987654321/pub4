# frozen_string_literal: true

require "test_helper"

class HealthControllerTest < ActionDispatch::IntegrationTest
  test "health returns ok json" do
    get "/health"

    assert_response :success
    assert_equal({ "status" => "ok" }, JSON.parse(response.body))
  end

  test "rails health check is exempt from container warmup" do
    Rails.application.config.x.master_container = nil

    get "/up"

    assert_response :success
  end
end