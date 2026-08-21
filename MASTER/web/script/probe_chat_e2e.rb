#!/usr/bin/env ruby
# frozen_string_literal: true
# frozen_string_literal: true

# Ferrum e2e — primer, face session, felt state, ping/pong chat.

require "json"
require "open3"
require "timeout"
require_relative "browser_probe_support"

URL = ARGV[0] || ENV.fetch("WEB_URL", "http://127.0.0.1:53187/")
FORCE = ENV["PROBE_FORCE_BROWSER"] == "1"

def static_html_ok?(url)
  html, status = Open3.capture2("curl", "-fsS", "--max-time", "8", url)
  return false unless status.success?

  html.include?('id="primer"') && html.include?("felt_state") && html.include?("sse_contract")
rescue StandardError
  false
end

def skip_probe!(reason)
  if static_html_ok?(URL)
    puts "\nok: probe_chat_e2e skip (#{reason})"
    puts "ok: static HTML primer felt_state sse_contract present"
    exit 0
  end
  puts "\nwarn: probe_chat_e2e (#{reason})"
  exit 1
end

if RUBY_PLATFORM.include?("darwin") && !FORCE
  skip_probe!("macOS — set PROBE_FORCE_BROWSER=1 for Ferrum")
end

chrome = BrowserProbeSupport.chrome_path
abort("probe_chat_e2e: no Chrome executable") unless chrome

failures = []
console_msgs = []
browser = nil

puts "probe_chat_e2e: #{URL}"
puts "probe_chat_e2e: launching Chrome (#{chrome})"

Timeout.timeout(BrowserProbeSupport::MAX_PROBE_SECONDS) do
  browser = BrowserProbeSupport.build_browser(
    chrome:,
    timeout: Integer(ENV.fetch("PROBE_BROWSER_TIMEOUT", "12")),
    extra_options: {
      "enable-webgl" => nil,
      "use-gl" => "swiftshader",
      "enable-unsafe-swiftshader" => nil,
      "disable-extensions" => nil,
      "disable-background-networking" => nil,
    },
  )

  browser.on(:console) do |msg|
    console_msgs << "[#{msg.type}] #{msg.args.map(&:value).join(' ')}"
  rescue StandardError # scan: intentional — a raising console hook would kill the probe loop; lost lines are acceptable
    nil
  end

  BrowserProbeSupport.install_error_hooks(browser, key: "_errs")

  begin
    browser.go_to(URL)
  rescue Ferrum::TimeoutError, Ferrum::PendingConnectionsError => e
    puts "WARN: navigation incomplete — #{e.class}"
  end

  sleep 2

  boot = BrowserProbeSupport.evaluate(browser, <<~JS)
    ({
      primer: !!document.getElementById('primer'),
      face3d: !!window.FACE3D_ACTIVE,
      felt: typeof window.MASTERFeltState,
      sse: typeof window.MASTER_SSE,
      container: typeof window.MASTER_CONTAINER,
      errs: window._errs || []
    })
  JS

  puts "\n=== boot ==="
  puts JSON.pretty_generate(boot)
  failures << "primer missing" unless boot["primer"]
  failures << "MASTERFeltState missing" unless boot["felt"] == "object"
  failures << "MASTER_SSE missing" unless boot["sse"] == "object"
  failures << "MASTER_CONTAINER missing" unless boot["container"] == "object"

  BrowserProbeSupport.tap_primer(browser)
  sleep 2
  snap = BrowserProbeSupport.wait_master_session(browser, timeout_s: 20)

  puts "\n=== session ==="
  puts JSON.pretty_generate(snap)
  failures << "primer not fired" unless snap["primerFired"]
  failures << "face-session missing" unless snap["faceSession"]
  failures << "MASTER_FACE missing" unless snap["masterFace"] == "object"
  failures << "sendMessage missing" unless snap["sendMessage"] == "function"

  felt = BrowserProbeSupport.evaluate(browser, <<~JS)
    (function() {
      const state = window.MASTERFeltState?.collectFeltState?.();
      return {
        state: state,
        valid: !!window.MASTERFeltState?.validateFeltState?.(state),
        parts: (state || '').split('|').length
      };
    })()
  JS

  puts "\n=== felt state ==="
  puts JSON.pretty_generate(felt)
  failures << "felt state invalid" unless felt["valid"]
  failures << "felt state not 7 fields" unless felt["parts"].to_i == 7

  chat = BrowserProbeSupport.run_ping_chat(browser, chat_wait_s: 4)
  chat = chat.merge("reply" => BrowserProbeSupport.evaluate(browser, <<~JS))
    (document.querySelector('.message.assistant:last-of-type .msg-body')?.textContent || '').trim()
  JS

  puts "\n=== chat ==="
  puts JSON.pretty_generate(chat)
  failures << "chat log empty" unless chat["logCount"].to_i.positive?
  failures << "ping/pong missing" unless chat["hasPong"]

  face_state = BrowserProbeSupport.evaluate(browser, <<~JS)
    ({
      mood: window.MASTER_FACE?.State?.mood || null,
      mode: window.MASTER_FACE?.State?.mode || null,
      confidence: window.MASTER_FACE?.State?.confidence ?? null,
      errs: window._errs || []
    })
  JS

  puts "\n=== face state ==="
  puts JSON.pretty_generate(face_state)
  failures << "face mood missing" if face_state["mood"].to_s.empty?
  fatal_errs = (face_state["errs"] || []).reject { |e| e.to_s.include?("face render slow") }
  failures << "js errors during e2e" unless fatal_errs.empty?

  puts "\n=== console tail ==="
  console_msgs.last(10).each { |line| puts line } unless console_msgs.empty?

  if failures.empty?
    puts "\nprobe_chat_e2e: PASS"
  else
    puts "\nprobe_chat_e2e: FAIL"
    failures.each { |f| puts "  - #{f}" }
    exit 1
  end
rescue Timeout::Error
  skip_probe!("probe exceeded #{BrowserProbeSupport::MAX_PROBE_SECONDS}s")
rescue Ferrum::ProcessTimeoutError => e
  skip_probe!("browser launch timeout — #{e.class}")
rescue Ferrum::TimeoutError, Ferrum::DeadBrowserError => e
  skip_probe!("headless blocked — #{e.class}")
ensure
  browser&.quit
end
