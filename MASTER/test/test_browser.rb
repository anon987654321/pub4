# frozen_string_literal: true

# Browser integration test using Ferrum + local Chromium.
# Run: bundle exec ruby test/test_browser.rb
#
# NOTE: Browser must be created BEFORE minitest/autorun is loaded,
# otherwise Minitest's signal handlers break Ferrum's pipe reading.
#
# Requires ~300MB free RAM. On low-memory servers, tests are auto-skipped.
#
# WHY CHROME TESTS SKIP ON OPENBSD
#
# Chrome/Chromium exits with SIGSEGV (139) immediately on OpenBSD due to the
# W^X (Write XOR Execute) memory protection policy enforced by the kernel.
# Chrome's V8 engine — even with --jitless -- and its process model require
# mmap(PROT_WRITE|PROT_EXEC) pages that OpenBSD forbids at the OS level.
# No combination of flags (--no-sandbox, --single-process, --jitless,
# --disable-gpu) resolves this; a dedicated OpenBSD-patched Chromium port
# would be required.
#
# To run browser tests against the live server from a non-OpenBSD machine:
#   WEB_URL=https://ai.brgen.no bundle exec ruby test/test_browser.rb
#
# HTTP smoke tests (test_web_http.rb) cover: page load, overlay presence,
# JS syntax, metrics JSON, and SSE stream — and run fine on OpenBSD.

require "ferrum"
require "json"
require "net/http"
require "socket"

CHROME_PATH = %w[/usr/local/bin/chrome /usr/local/bin/chromium].find { |p| File.executable?(p) }
WEB_URL     = (ENV["WEB_URL"] || "http://localhost:10002").freeze

FREE_MEM_MB = begin
  # Use free + inactive pages — inactive pages are reclaimable by new processes.
  stats = `vmstat -s`
  free_pages     = stats[/(\d+) pages free/,    1].to_i
  inactive_pages = stats[/(\d+) pages inactive/, 1].to_i
  (free_pages + inactive_pages) * 4 / 1024  # 4KB pages → MB
rescue StandardError
  999
end

SKIP_REASON = if CHROME_PATH.nil?
  "Chromium not found"
elsif begin; TCPSocket.new("127.0.0.1", 10002).close; false; rescue StandardError; true; end
  "Web server not running on port 10002"
elsif FREE_MEM_MB < 300
  "Insufficient free memory (#{FREE_MEM_MB}MB < 300MB required for Chrome)"
end

# Start Chrome now, before minitest/autorun installs signal handlers.
FERRUM_BROWSER = if SKIP_REASON.nil?
  begin
    Ferrum::Browser.new(
      browser_path: CHROME_PATH,
      process_timeout: 30,
      timeout: 20,
      browser_options: {
        "headless"       => "new",
        "no-sandbox"     => nil,
        "single-process" => nil,
        "disable-gpu"    => nil,
        "disable-dev-shm-usage" => nil
      }
    )
  rescue StandardError => e
    warn "Chrome failed to start: #{e.message}"
    nil
  end
end

# Override SKIP_REASON if browser failed to start
BROWSER_SKIP = SKIP_REASON || (FERRUM_BROWSER.nil? ? "Chrome failed to start" : nil)

require "minitest/autorun"

class TestBrowserUI < Minitest::Test
  def skip_if_unavailable
    skip BROWSER_SKIP if BROWSER_SKIP
  end

  def fresh_page
    pg = FERRUM_BROWSER.create_page
    pg.go_to(WEB_URL)
    pg.network.wait_for_idle
    pg
  rescue Ferrum::DeadBrowserError => e
    skip "Chrome died (OOM): #{e.message}"
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

  # Uses plain HTTP — no browser page needed for a JSON endpoint.
  def test_05_metrics_endpoint_json
    skip "Web server not running" unless begin
      TCPSocket.new("127.0.0.1", 10002).close
      true
    rescue StandardError
      false
    end
    uri  = URI("#{WEB_URL}/chat/metrics")
    body = Net::HTTP.get(uri)
    data = JSON.parse(body)
    assert data.key?("model"),         "metrics should include 'model'"
    assert data.key?("tokens"),        "metrics should include 'tokens'"
    assert data.key?("open_breakers"), "metrics should include 'open_breakers'"
  rescue JSON::ParserError => e
    flunk "metrics returned invalid JSON: #{e.message}"
  end
end

Minitest.after_run { FERRUM_BROWSER&.quit rescue nil }
