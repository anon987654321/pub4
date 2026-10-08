# frozen_string_literal: true

# Browser integration test for the MASTER face shell (primer → prompt unlock).
# Run: bundle exec ruby test/test_browser.rb
#
# Against production from a Mac/Linux host with Chrome:
#   WEB_URL=https://ai.brgen.no bundle exec ruby test/test_browser.rb

require "ferrum"
require "json"
require "net/http"
require "socket"

CHROME_PATHS = [
  ENV["CHROME_PATH"],
  "/usr/local/bin/chrome",
  "/usr/local/bin/chromium",
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
  "/Applications/Chromium.app/Contents/MacOS/Chromium",
].compact.freeze
CHROME_PATH = CHROME_PATHS.find { |path| File.executable?(path) }

WEB_PORT    = Integer(ENV.fetch("MASTER_WEB_PORT", "53187"))
WEB_URL     = (ENV["WEB_URL"] || "http://localhost:#{WEB_PORT}").freeze
LOCAL_PROBE = WEB_URL.include?("localhost") || WEB_URL.include?("127.0.0.1")

FREE_MEM_MB = begin
  stats = `vmstat -s`
  free_pages     = stats[/(\d+) pages free/,    1].to_i
  inactive_pages = stats[/(\d+) pages inactive/, 1].to_i
  (free_pages + inactive_pages) * 4 / 1024
rescue StandardError
  999
end

SKIP_REASON = if CHROME_PATH.nil?
  "Chromium not found"
elsif LOCAL_PROBE && begin
  TCPSocket.new("127.0.0.1", WEB_PORT).close
  false
rescue StandardError
  true
end
  "Web server not running on port #{WEB_PORT}"
elsif FREE_MEM_MB < 300
  "Insufficient free memory (#{FREE_MEM_MB}MB < 300MB required for Chrome)"
end

FERRUM_BROWSER = if SKIP_REASON.nil?
  begin
    Ferrum::Browser.new(
      browser_path: CHROME_PATH,
      headless: "new",
      process_timeout: 45,
      timeout: LOCAL_PROBE ? 30 : 90,
      browser_options: {
        "no-sandbox"            => nil,
        "disable-dev-shm-usage" => nil,
        "ignore-certificate-errors" => nil,
      },
    )
  rescue StandardError => e
    warn "Chrome failed to start: #{e.message}"
    nil
  end
end

BROWSER_SKIP = SKIP_REASON || (FERRUM_BROWSER.nil? ? "Chrome failed to start" : nil)

require "minitest/autorun"

class TestBrowserUI < Minitest::Test
  def skip_if_unavailable
    skip BROWSER_SKIP if BROWSER_SKIP
  end

  def fresh_page
    pg = FERRUM_BROWSER.create_page
    pg.go_to(WEB_URL)
    wait_until(timeout: LOCAL_PROBE ? 10 : 30) do
      pg.evaluate("document.readyState === 'complete' && !!document.getElementById('primer')")
    end
    pg
  rescue Ferrum::DeadBrowserError => e
    skip "Chrome died (OOM): #{e.message}"
  rescue Ferrum::TimeoutError => e
    skip "Page load timed out: #{e.message}"
  end

  def teardown
    FERRUM_BROWSER&.pages&.each(&:close) rescue nil
  end

  def wait_until(timeout:, interval: 0.1)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    loop do
      return true if yield
      return false if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

      sleep interval
    end
  end

  def test_01_page_loads_with_primer
    skip_if_unavailable
    pg = fresh_page
    assert pg.at_css("#primer"), "primer element missing"
    assert pg.at_css("#face"), "face canvas missing"
    assert pg.at_css("#zsh"), "prompt shell missing"
  end

  def test_02_primer_dismisses_on_tap
    skip_if_unavailable
    pg = fresh_page
    pg.mouse.click(x: 300, y: 400)
    primer_gone = wait_until(timeout: LOCAL_PROBE ? 10 : 20) do
      pg.evaluate("!document.getElementById('primer')")
    end
    assert primer_gone, "primer should be removed after tap"
    assert pg.evaluate("document.getElementById('zsh').classList.contains('live')"),
           "zsh should have live class after tap"
    assert pg.evaluate("window._primerFired === true"), "_primerFired should be true"
  end

  def test_03_face_runtime_eventually_ready
    skip_if_unavailable
    pg = fresh_page
    pg.mouse.click(x: 300, y: 400)
    ready = wait_until(timeout: LOCAL_PROBE ? 45 : 75, interval: 0.5) do
      pg.evaluate("typeof window.MASTER_FACE === 'object' && !!window.MASTER_FACE.startEverything")
    end
    assert ready, "MASTER_FACE should become available after tap"
  end

  def test_04_chat_ping_after_boot
    skip_if_unavailable
    pg = fresh_page
    pg.mouse.click(x: 300, y: 400)
    assert wait_until(timeout: LOCAL_PROBE ? 10 : 25) { pg.at_css("#zin") }, "chat input did not become ready"
    pg.at_css("#zin").focus
    pg.keyboard.type("ping")
    pg.keyboard.type(:Return)
    response = ""
    wait_until(timeout: 35, interval: 0.25) do
      response = pg.evaluate("document.getElementById('chat-log').textContent").strip
      !response.empty?
    end
    refute_empty response, "chat-log should contain a response to 'ping'"
  end
end

Minitest.after_run { FERRUM_BROWSER&.quit rescue nil }
