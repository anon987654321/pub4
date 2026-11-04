# frozen_string_literal: true

require "test_helper"

class RuntimeControllerTest < ActionDispatch::IntegrationTest
  test "status reports warming when container absent" do
    Rails.application.config.x.master_container = nil

    get "/runtime/status"

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal false, body["ready"]
    assert_equal "booting", body["model"]
    assert body.key?("uptime_ms")
    assert body.key?("build")
    assert body.key?("face_boot_ms")
    assert body.key?("particle_worker_alive")
  end

  test "status reports ready when container present" do
    fake = { agent: Struct.new(:model).new("anthropic/claude-sonnet") }
    Rails.application.config.x.master_container = fake

    get "/runtime/status"

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal true, body["ready"]
    assert_equal "claude-sonnet", body["model"]
  ensure
    Rails.application.config.x.master_container = nil
  end

  test "status reports the same build the page names its cache after" do
    get "/runtime/status"

    assert_equal Rails.application.config.x.cache_version, JSON.parse(response.body)["build"]
    refute_nil JSON.parse(response.body)["build"]
  end
end
