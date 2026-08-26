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

  # Plain minitest: mocha is not in this bundle, so `any_instance` does not
  # exist. Redefining the predicate on the class and putting it back is the
  # smallest way to ask what /health does when one check is false.
  def with_check(name, value)
    original = HealthController.instance_method(name)
    HealthController.define_method(name) { value }
    yield
  ensure
    HealthController.define_method(name, original)
  end

  # ai.brgen.no answered every /health with a hard 503 for as long as the daemon
  # could not read the repository, and the browser polls that endpoint on an
  # interval from two separate places — so the face wired itself against a
  # service insisting it was unavailable while every other request it made
  # succeeded. Measured live 2026-08-26: tts true, git false, status
  # "unavailable", HTTP 503.
  #
  # git answers "can this process name the commit it is running", which is
  # provenance, not liveness. A service that cannot name its own SHA still
  # serves every request correctly, so it degrades and must never 503.
  test "an unreadable repository degrades rather than taking the service down" do
    with_check(:git_healthy?, false) do
      get "/health"

      assert_response :success, "provenance must not 503 a service that is answering"
      body = JSON.parse(response.body)
      assert_equal "degraded", body["status"]
      assert_equal false, body.dig("checks", "git")
      assert_equal true, body.dig("checks", "tts")
    end
  end

  # The other direction, so the downgrade above cannot quietly swallow the case
  # 503 exists for. TTS is the one check that stays critical.
  test "a tts capability outage still 503s" do
    with_check(:tts_healthy?, false) do
      get "/health"

      assert_response :service_unavailable
      assert_equal "unavailable", JSON.parse(response.body)["status"]
    end
  end

  test "rails health check is exempt from container warmup" do
    Rails.application.config.x.master_container = nil

    get "/up"

    assert_response :success
  end
end
