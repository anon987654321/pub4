# frozen_string_literal: true

# Browser integration test using Ferrum + local Chromium.
# Requires: /usr/local/bin/chrome, web server on port 10002.
# Run: bundle exec ruby test/test_browser.rb

require_relative "test_helper"
require "ferrum"

WEB_URL = "http://localhost:10002".freeze

CHROME_PATH = %w[/usr/local/bin/chrome /usr/local/bin/chromium].find { |p| File.executable?(p) }

def server_up?
  require "socket"
  TCPSocket.new("127.0.0.1", 10002).close
  true
rescue Errno::ECONNREFUSED, Errno::ETIMEDOUT
  false
end

SKIP_BROWSER = CHROME_PATH.nil? || !server_up?

class TestBrowserUI < Minitest::Test
  # Shared browser + page — Chrome starts once for the full suite.
  @@browser = nil
  @@page    = nil

  def self.browser
    @@browser ||= Ferrum::Browser.new(
      browser_path: CHROME_PATH,
      process_timeout: 25,
      timeout: 20,
      browser_options: { "headless" => "new", "no-sandbox" => nil }
    )
  end

  def self.page
    @@page ||= browser.create_page
  end

  Minitest.after_run do
    @@browser&.quit
    @@browser = nil
    @@page    = nil
  end

  # Bypass the 10s test_helper Timeout — browser tests are slow by nature.
  def run(*args)
    skip "Chromium or web server not available" if SKIP_BROWSER
    run_without_timeout(*args)
  end

  def fresh_page
    pg = TestBrowserUI.page
    pg.go_to(WEB_URL)
    pg.network.wait_for_idle
    pg
  end

  def test_page_loads_with_overlay
    pg = fresh_page
    assert pg.at_css("#overlay"), "overlay element missing"
    assert !pg.evaluate("document.getElementById('overlay').hidden"),
           "overlay should be visible on load"
  end

  def test_overlay_dismisses_on_click
    pg = fresh_page
    pg.at_css("#overlay").click
    sleep 1.5
    assert pg.evaluate("document.getElementById('overlay').hidden"),
           "overlay should be hidden after click"
  end

  def test_input_active_after_overlay_dismissed
    pg = fresh_page
    pg.at_css("#overlay").click
    sleep 1.5
    assert pg.evaluate("document.getElementById('input-field').classList.contains('active')"),
           "input-field should have 'active' class"
  end

  def test_chat_receives_response
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

  def test_metrics_endpoint_json
    pg = TestBrowserUI.page
    pg.go_to("#{WEB_URL}/chat/metrics")
    pg.network.wait_for_idle
    data = JSON.parse(pg.evaluate("document.body.textContent"))
    assert data.key?("model"),     "metrics should include 'model'"
    assert data.key?("token_est"), "metrics should include 'token_est'"
  rescue JSON::ParserError => e
    flunk "metrics returned invalid JSON: #{e.message}"
  end
end
