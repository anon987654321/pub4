# frozen_string_literal: true

# Browser integration test using Ferrum + local Chromium.
# Run: bundle exec ruby test/test_browser.rb
#
# NOTE: Browser must be created BEFORE minitest/autorun is loaded,
# otherwise Minitest's signal handlers break Ferrum's pipe reading.
#
# Requires ~250MB free RAM. On low-memory servers, tests are auto-skipped.

require "ferrum"
require "json"
require "socket"

CHROME_PATH = %w[/usr/local/bin/chrome /usr/local/bin/chromium].find { |p| File.executable?(p) }
WEB_URL     = "http://localhost:10002".freeze

FREE_MEM_MB = begin
  line = `vmstat`.lines.last.to_s
  line.split[4].to_i / 1024  # fre column is in KB on OpenBSD
rescue
  999
end

SKIP_REASON = if CHROME_PATH.nil?
  "Chromium not found"
elsif begin; TCPSocket.new("127.0.0.1", 10002).close; false; rescue; true; end
  "Web server not running on port 10002"
elsif FREE_MEM_MB < 250
  "Insufficient free memory (#{FREE_MEM_MB}MB < 250MB required for Chrome)"
end

# Start Chrome now, before minitest/autorun installs signal handlers.
FERRUM_BROWSER = if SKIP_REASON.nil?
  Ferrum::Browser.new(
    browser_path: CHROME_PATH,
    process_timeout: 30,
    timeout: 20,
    browser_options: {
      "headless"       => "new",
      "no-sandbox"     => nil,
      "single-process" => nil,
      "disable-gpu"    => nil
    }
  )
end

require "minitest/autorun"

class TestBrowserUI < Minitest::Test
  def skip_if_unavailable
    skip SKIP_REASON if SKIP_REASON
  end

  def fresh_page
    pg = FERRUM_BROWSER.create_page
    pg.go_to(WEB_URL)
    pg.network.wait_for_idle
    pg
  end

  def teardown
    FERRUM_BROWSER&.pages&.each(&:close) rescue nil
  end

  def test_01_page_loads_with_overlay
    skip_if_unavailable
    pg = fresh_page
    assert pg.at_css("#overlay"), "overlay element missing"
    assert !pg.evaluate("document.getElementById('overlay').hidden"),
           "overlay should be visible on load"
  end

  def test_02_overlay_dismisses_on_click
    skip_if_unavailable
    pg = fresh_page
    pg.at_css("#overlay").click
    sleep 1.5
    assert pg.evaluate("document.getElementById('overlay').hidden"),
           "overlay should be hidden after click"
  end

  def test_03_input_active_after_overlay_dismissed
    skip_if_unavailable
    pg = fresh_page
    pg.at_css("#overlay").click
    sleep 1.5
    assert pg.evaluate("document.getElementById('input-field').classList.contains('active')"),
           "input-field should have 'active' class"
  end

  def test_04_chat_receives_response
    skip_if_unavailable
    pg = fresh_page
    pg.at_css("#overlay").click
    sleep 1.2
    pg.at_css("#input-field input[type=text]").focus
    pg.keyboard.type("ping")
    pg.keyboard.type(:Return)
    deadline = Time.now + 30
    response = ""
    loop do
      response = pg.evaluate("document.getElementById('chat-log').textContent").strip
      break unless response.empty?
      break if Time.now > deadline
      sleep 1
    end
    refute_empty response, "chat-log should contain a response to 'ping'"
  end

  def test_05_metrics_endpoint_json
    skip_if_unavailable
    pg = FERRUM_BROWSER.create_page
    pg.go_to("#{WEB_URL}/chat/metrics")
    pg.network.wait_for_idle
    data = JSON.parse(pg.evaluate("document.body.textContent"))
    assert data.key?("model"),     "metrics should include 'model'"
    assert data.key?("token_est"), "metrics should include 'token_est'"
  rescue JSON::ParserError => e
    flunk "metrics returned invalid JSON: #{e.message}"
  ensure
    pg&.close rescue nil
  end
end

Minitest.after_run { FERRUM_BROWSER&.quit }
