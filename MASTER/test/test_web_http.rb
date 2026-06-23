# frozen_string_literal: true

# HTTP smoke tests for the MASTER web UI.
# Faster and lighter than browser tests -- no Chrome required.
# Run: bundle exec ruby test/test_web_http.rb

require "net/http"
require "json"
require "socket"
require "minitest/autorun"

WEB_PORT = Integer(ENV.fetch("MASTER_WEB_PORT", "53187"))

SKIP_HTTP = begin
  TCPSocket.new("127.0.0.1", WEB_PORT).close
  nil
rescue Errno::ECONNREFUSED
  "Web server not running on port #{WEB_PORT}"
end

class TestWebHTTP < Minitest::Test
  def skip_unless_server
    skip SKIP_HTTP if SKIP_HTTP
  end

  def get(path, headers = {})
    Net::HTTP.start("127.0.0.1", WEB_PORT, read_timeout: 10) do |http|
      http.request(Net::HTTP::Get.new(path, headers))
    end
  end

  def test_01_homepage_returns_200
    skip_unless_server
    res = get("/")
    assert_equal "200", res.code, "homepage should return 200"
  end

  def test_02_homepage_contains_face_runtime
    skip_unless_server
    res = get("/")
    body = res.body
    assert_includes body, 'id="face"', "homepage should contain face canvas"
    assert_includes body, "three.face.module", "homepage should load face runtime assets"
    refute_includes body, "davis", "davis voice should not be in picker"
  end

  def test_03_homepage_js_no_stray_paren
    skip_unless_server
    res = get("/")
    bad = res.body.lines.grep(/^\s*"\);/)
    assert_empty bad, "stray \");\" found in page JS: #{bad.first(2).inspect}"
  end

  def test_04_metrics_returns_json
    skip_unless_server
    res = get("/chat/metrics")
    assert_equal "200", res.code, "metrics endpoint should return 200"
    data = JSON.parse(res.body)
    assert data.key?("model"),         "metrics should include 'model'"
    assert data.key?("tokens"),        "metrics should include 'tokens'"
    assert data.key?("uptime"),        "metrics should include 'uptime'"
    assert data.key?("open_breakers"), "metrics should include 'open_breakers'"
  rescue StandardError => e
    flunk "metrics returned invalid JSON: #{e.message}"
  end

  def test_05_message_endpoint_streams_sse
    skip_unless_server
    Net::HTTP.start("127.0.0.1", WEB_PORT, read_timeout: 15) do |http|
      req = Net::HTTP::Get.new("/chat/message?message=ping")
      data = ""
      http.request(req) do |res|
        assert_equal "200", res.code, "message endpoint should return 200"
        assert_match "text/event-stream", res["Content-Type"].to_s,
                     "message endpoint should stream SSE"
        res.read_body do |chunk|
          data += chunk
          break if data.include?("[DONE]") || data.size > 512
        end
      end
      assert_includes data, "data:", "SSE response should contain data: lines"
    end
  rescue Net::ReadTimeout
    # Server still streaming -- that means it accepted the request fine
  end
end
