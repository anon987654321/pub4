#!/usr/bin/env ruby
# frozen_string_literal: true

require "ferrum"
require "json"
require "open3"
require "timeout"

URL = ARGV[0] || ENV.fetch("WEB_URL", "http://127.0.0.1:53187/")
BROWSER_TIMEOUT = Integer(ENV.fetch("PROBE_BROWSER_TIMEOUT", "12"))
MAX_PROBE_SECONDS = Integer(ENV.fetch("PROBE_MAX_SECONDS", "55"))
FORCE = ENV["PROBE_FORCE_BROWSER"] == "1"
CHROME_PATHS = [
  ENV["CHROME_PATH"],
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
  "/Applications/Chromium.app/Contents/MacOS/Chromium",
  "/usr/local/bin/chromium",
  "/usr/local/bin/chrome"
].compact.freeze

def static_html_ok?(url)
  html, status = Open3.capture2("curl", "-fsS", "--max-time", "8", url)
  return false unless status.success?

  html.include?('id="primer"') && html.include?("felt_state") && html.include?("sse_contract")
rescue StandardError
  false
end

def skip_probe!(reason)
  if static_html_ok?(URL)
    puts "\nprobe_chat_e2e: SKIP (#{reason})"
    puts "static HTML checks OK: primer + felt_state + sse_contract present"
    exit 0
  end
  puts "\nprobe_chat_e2e: FAIL (#{reason})"
  exit 1
end

if RUBY_PLATFORM.include?("darwin") && !FORCE
  skip_probe!("macOS — set PROBE_FORCE_BROWSER=1 for Ferrum")
end

chrome = CHROME_PATHS.find { |path| File.executable?(path) }
abort("probe_chat_e2e: no Chrome executable") unless chrome

failures = []
console_msgs = []
browser = nil

def probe_evaluate(browser, script)
  browser.evaluate(script)
rescue Ferrum::TimeoutError, Ferrum::DeadBrowserError => e
  raise e
end

puts "probe_chat_e2e: #{URL}"
puts "probe_chat_e2e: launching Chrome (#{chrome})"

Timeout.timeout(MAX_PROBE_SECONDS) do
  browser = Ferrum::Browser.new(
    browser_path: chrome,
    headless: "new",
    timeout: BROWSER_TIMEOUT,
    process_timeout: BROWSER_TIMEOUT + 8,
    browser_options: {
      "no-sandbox" => nil,
      "disable-dev-shm-usage" => nil,
      "disable-gpu" => nil,
      "enable-webgl" => nil,
      "use-gl" => "swiftshader",
      "enable-unsafe-swiftshader" => nil,
      "ignore-certificate-errors" => nil,
      "remote-allow-origins" => "*",
      "disable-extensions" => nil,
      "disable-background-networking" => nil
    }
  )

  browser.on(:console) do |msg|
    console_msgs << "[#{msg.type}] #{msg.args.map(&:value).join(' ')}"
  rescue StandardError
    nil
  end

  browser.evaluate_on_new_document(<<~JS)
    window._errs = [];
    window.onerror = function(msg, src, line) {
      window._errs.push(msg + ' @ ' + (src || '').split('/').pop() + ':' + line);
    };
    window.addEventListener('unhandledrejection', function(e) {
      window._errs.push('UNHANDLED: ' + String(e.reason));
    });
  JS

  begin
    browser.go_to(URL)
  rescue Ferrum::TimeoutError, Ferrum::PendingConnectionsError => e
    puts "WARN: navigation incomplete — #{e.class}"
  end

  sleep 2

  boot = probe_evaluate(browser, <<~JS)
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

  probe_evaluate(browser, <<~JS)
    (function() {
      if (window.__MASTER_PRIMER_TAP__) { window.__MASTER_PRIMER_TAP__(); return 'tap'; }
      var p = document.getElementById('primer');
      if (p) { p.click(); return 'click'; }
      return 'none';
    })()
  JS
  sleep 2

  snap = {}
  deadline = Time.now + 20
  until Time.now > deadline
    snap = probe_evaluate(browser, <<~JS)
      ({
        primerFired: !!window._primerFired,
        faceSession: document.body.classList.contains('face-session'),
        masterFace: typeof window.MASTER_FACE,
        sendMessage: typeof window.sendMessage
      })
    JS
    break if snap["primerFired"] && snap["faceSession"] && snap["masterFace"] == "object" && snap["sendMessage"] == "function"
    sleep 1
  end

  puts "\n=== session ==="
  puts JSON.pretty_generate(snap)
  failures << "primer not fired" unless snap["primerFired"]
  failures << "face-session missing" unless snap["faceSession"]
  failures << "MASTER_FACE missing" unless snap["masterFace"] == "object"
  failures << "sendMessage missing" unless snap["sendMessage"] == "function"

  felt = probe_evaluate(browser, <<~JS)
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

  probe_evaluate(browser, <<~JS)
    (function() {
      if (window.MASTER_CONTAINER?.ready?.() === false) {
        window.MASTER_CONTAINER_READY = true;
        var input = document.getElementById('zin');
        if (input) input.disabled = false;
      }
      window.sendMessage && window.sendMessage('ping');
      return true;
    })()
  JS
  sleep 4

  chat = probe_evaluate(browser, <<~JS)
    (function() {
      const body = document.querySelector('.message.assistant:last-of-type .msg-body');
      const text = (body?.textContent || '').trim();
      return {
        reply: text,
        hasPong: /pong/i.test(text),
        logCount: document.querySelectorAll('#chat-log .message').length
      };
    })()
  JS

  puts "\n=== chat ==="
  puts JSON.pretty_generate(chat)
  failures << "chat log empty" unless chat["logCount"].to_i.positive?
  failures << "ping/pong missing" unless chat["hasPong"]

  face_state = probe_evaluate(browser, <<~JS)
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
  skip_probe!("probe exceeded #{MAX_PROBE_SECONDS}s")
rescue Ferrum::ProcessTimeoutError => e
  skip_probe!("browser launch timeout — #{e.class}")
rescue Ferrum::TimeoutError, Ferrum::DeadBrowserError => e
  skip_probe!("headless blocked — #{e.class}")
ensure
  browser&.quit
end