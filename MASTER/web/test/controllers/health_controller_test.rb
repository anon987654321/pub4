# frozen_string_literal: true

require "test_helper"

class HealthControllerTest < ActionDispatch::IntegrationTest
  test "health returns status and dependency checks" do
    get "/health"

    assert_response :success
    body = JSON.parse(response.body)
    assert_includes %w[ok degraded], body["status"]
    assert body["checks"].key?("tts")
    assert_equal true, body.dig("checks", "tts")
    assert body["checks"].key?("git")
    assert body["deploy"].key?("voice_policy")
    assert_equal Master::Voice::Policy.single_voice_key.to_s, body.dig("deploy", "voice_policy", "single_voice")
    assert body["deploy"].key?("tts_socket")
    assert body["deploy"].key?("face_runtime_digest")
  end

  test "rails health check is exempt from container warmup" do
    Rails.application.config.x.master_container = nil

    get "/up"

    assert_response :success
  end
end
