#!/usr/bin/env ruby
# frozen_string_literal: true

# Ferrum browser crawl — element presence and light interaction checks.
# Run from MASTER so Ferrum (test group) resolves:
#   cd MASTER && BUNDLE_WITH=test bundle exec ruby ../DEPLOY/rails/crawl_browser.rb
#   cd MASTER && BUNDLE_WITH=test bundle exec ruby ../DEPLOY/rails/crawl_browser.rb --public

require "json"
require "optparse"
require "socket"
require "timeout"
require "yaml"

ROOT = File.expand_path("../..", __dir__)
MANIFEST = File.join(__dir__, "crawl_manifest.yml")
APPS_YML = File.join(__dir__, "apps.yml")

options = { public: false, skip_closed: true, force: ENV["PROBE_FORCE_BROWSER"] == "1" }
OptionParser.new do |parser|
  parser.banner = "Usage: crawl_browser.rb [--public] [--strict] [--force]"
  parser.on("--public", "Use HTTPS domains from apps.yml") { options[:public] = true }
  parser.on("--strict", "Fail when target ports are closed") { options[:skip_closed] = false }
  parser.on("--force", "Run even without Chrome (will fail)") { options[:force] = true }
end.parse!

CHROME_PATHS = [
  ENV["CHROME_PATH"],
  "/usr/local/bin/chromium",
  "/usr/local/bin/chrome",
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
  "/Applications/Chromium.app/Contents/MacOS/Chromium"
].compact.freeze

BROWSER_TIMEOUT = Integer(ENV.fetch("PROBE_BROWSER_TIMEOUT", "15"))
MAX_PROBE_SECONDS = Integer(ENV.fetch("PROBE_MAX_SECONDS", "75"))

def load_manifest
  YAML.safe_load(File.read(MANIFEST)) || {}
end

def load_apps
  YAML.safe_load(File.read(APPS_YML)).fetch("apps")
end

def port_open?(host, port, timeout: 0.5)
  Socket.tcp(host, port, connect_timeout: timeout).close
  true
rescue StandardError
  false
end

def chrome_path
  CHROME_PATHS.find { |path| File.executable?(path) }
end

def base_url(name, port, apps, public:)
  if public && apps[name]
    "https://#{apps[name]["domain"]}"
  else
    "http://127.0.0.1:#{port}"
  end
end

def install_error_hooks(browser)
  browser.evaluate_on_new_document(<<~JS)
    window._crawlErrs = [];
    window.onerror = function(msg, src, line) {
      window._crawlErrs.push(String(msg) + ' @ ' + (src || '').split('/').pop() + ':' + line);
    };
    window.addEventListener('unhandledrejection', function(e) {
      window._crawlErrs.push('UNHANDLED: ' + String(e.reason));
    });
  JS
end

def evaluate(browser, script, attempts: 3)
  attempts.times do |i|
    return browser.evaluate(script)
  rescue Ferrum::TimeoutError, Ferrum::DeadBrowserError => e
    raise e if i + 1 >= attempts
    sleep 1
  end
end

def run_checks(browser, checks, label, failures)
  Array(checks).each do |check|
    case check["type"].to_s
    when "selector"
      sel = check["css"] || (check["id"] ? "##{check["id"]}" : nil)
      failures << "#{label}: missing selector #{sel.inspect}" unless sel && evaluate(browser, "!!document.querySelector(#{sel.to_json})")
    when "js"
      ok = evaluate(browser, "(#{check['expr']})")
      failures << "#{label}: js check failed — #{check['expr']}" unless ok
    when "text_absent"
      body = evaluate(browser, "document.body ? document.body.innerText : ''").to_s
      failures << "#{label}: page contains #{check['value'].inspect}" if body.include?(check["value"].to_s)
    else
      failures << "#{label}: unknown browser check type #{check['type'].inspect}"
    end
  rescue StandardError => e
    failures << "#{label}: #{check['type']} — #{e.class}: #{e.message}"
  end
end

def tap_primer(browser)
  evaluate(browser, <<~JS)
    (function() {
      if (window.__MASTER_PRIMER_TAP__) { window.__MASTER_PRIMER_TAP__(); return true; }
      var p = document.getElementById('primer');
      if (p) { p.click(); return true; }
      return false;
    })()
  JS
end

def wait_master_session(browser, timeout_s: 20)
  deadline = Time.now + timeout_s
  snap = {}
  until Time.now >= deadline
    snap = evaluate(browser, <<~JS)
      ({
        primerFired: !!window._primerFired,
        faceSession: document.body.classList.contains('face-session'),
        masterFace: typeof window.MASTER_FACE,
        sendMessage: typeof window.sendMessage
      })
    JS
    break if snap["primerFired"] && snap["faceSession"] && snap["masterFace"] == "object"
    sleep 1
  end
  snap
end

def run_master_session(browser, session, label, failures)
  return unless session.is_a?(Hash)

  tap_primer(browser) if session["tap_primer"]
  sleep Integer(session.fetch("wait_s", 2))
  snap = wait_master_session(browser, timeout_s: Integer(session.fetch("session_timeout_s", 20))) if session["tap_primer"]
  if session["tap_primer"]
    failures << "#{label}: primer not fired" unless snap["primerFired"]
    failures << "#{label}: face-session class missing" unless snap["faceSession"]
    failures << "#{label}: MASTER_FACE missing" unless snap["masterFace"] == "object"
  end

  return unless session["ping_chat"]

  evaluate(browser, <<~JS)
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
  sleep Integer(session.fetch("chat_wait_s", 4))
  chat = evaluate(browser, <<~JS)
    ({
      hasPong: /pong/i.test((document.querySelector('.message.assistant:last-of-type .msg-body')?.textContent || '')),
      logCount: document.querySelectorAll('#chat-log .message').length
    })
  JS
  failures << "#{label}: chat log empty" unless chat["logCount"].to_i.positive?
  failures << "#{label}: ping/pong missing" unless chat["hasPong"]
end

def crawl_target(browser, name, url, browser_spec, failures)
  label = "#{name} browser"
  warmup = Integer(browser_spec.fetch("warmup_s", 2))
  begin
    browser.go_to(url)
  rescue Ferrum::TimeoutError, Ferrum::PendingConnectionsError
    nil
  end
  sleep warmup
  run_checks(browser, browser_spec["checks"], label, failures)
  run_master_session(browser, browser_spec["session"], label, failures) if browser_spec["session"]
  errs = evaluate(browser, "window._crawlErrs || []")
  fatal = Array(errs).reject { |e| e.to_s.include?("face render slow") }
  failures << "#{label}: js errors — #{fatal.join('; ')}" unless fatal.empty?
end

chrome = chrome_path
unless chrome || options[:force]
  reason = if RUBY_PLATFORM.include?("darwin") && !options[:force]
             "macOS — set PROBE_FORCE_BROWSER=1 or run on VPS"
           else
             "no Chrome/Chromium executable"
           end
  puts "crawl-browser: skip — #{reason}"
  exit 0
end

begin
  require "ferrum"
rescue LoadError
  warn "crawl-browser: ferrum not loaded — run from MASTER with BUNDLE_WITH=test bundle exec"
  exit 1
end

manifest = load_manifest
apps = load_apps
failures = []
skips = []
targets = []

manifest.fetch("master", {}).then do |spec|
  next unless spec["browser"]
  targets << ["master", spec["port"], spec["browser"]]
end
manifest.fetch("apps", {}).each do |name, spec|
  next unless spec["browser"]
  targets << [name, spec["port"], spec["browser"]]
end

if targets.empty?
  puts "crawl-browser: no browser sections in crawl_manifest.yml"
  exit 0
end

Timeout.timeout(MAX_PROBE_SECONDS) do
  browser = Ferrum::Browser.new(
    browser_path: chrome,
    headless: "new",
    timeout: BROWSER_TIMEOUT,
    process_timeout: BROWSER_TIMEOUT + 12,
    pending_connection_errors: false,
    browser_options: {
      "no-sandbox" => nil,
      "disable-dev-shm-usage" => nil,
      "disable-gpu" => nil,
      "ignore-certificate-errors" => nil,
      "remote-allow-origins" => "*"
    }
  )
  install_error_hooks(browser)

  targets.each do |name, port, browser_spec|
    unless options[:public]
      open = port_open?("127.0.0.1", port)
      unless open
        if options[:skip_closed]
          skips << "#{name}: port #{port} closed"
          next
        end
        failures << "#{name}: port #{port} closed"
        next
      end
    end

    url = "#{base_url(name, port, apps, public: options[:public])}/"
    crawl_target(browser, name, url, browser_spec, failures)
  end

  browser.quit
end

skips.each { |line| puts "crawl-browser: skip — #{line}" }
if failures.empty?
  puts "crawl-browser: clean (#{targets.size} targets, #{skips.size} skipped)"
  exit 0
end

failures.each { |line| warn "crawl-browser: #{line}" }
warn "crawl-browser: #{failures.size} failure(s)"
exit 1
rescue Timeout::Error
  warn "crawl-browser: timeout after #{MAX_PROBE_SECONDS}s"
  exit 1
rescue Ferrum::ProcessTimeoutError, Ferrum::DeadBrowserError => e
  warn "crawl-browser: browser unavailable — #{e.class}"
  exit options[:skip_closed] ? 0 : 1
end