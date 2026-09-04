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

  # A 503 that will not say what broke sends the operator back to re-derive it
  # on a box that is already failing, and the reason is the whole value of
  # asking the worker: `cannot load such file -- rb_edge_tts` names the fix.
  test "a tts outage reports why, not just false" do
    with_check(:tts_healthy?, false) do
      with_check(:tts_blocker, "worker selftest exited 1: cannot load such file -- rb_edge_tts") do
        get "/health"

        assert_response :service_unavailable
        body = JSON.parse(response.body)
        assert_includes body.dig("blocked", "tts").to_s, "rb_edge_tts"
      end
    end
  end

  # The healthy payload keeps its shape. Callers parse this on an interval from
  # two places in the browser, and a key that appears only sometimes is a key
  # every one of them has to guard.
  test "a healthy response carries no blocked key" do
    get "/health"

    assert_response :success
    refute JSON.parse(response.body).key?("blocked")
  end

  test "rails health check is exempt from container warmup" do
    Rails.application.config.x.master_container = nil

    get "/up"

    assert_response :success
  end
end
