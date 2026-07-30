#!/usr/bin/env ruby
# frozen_string_literal: true

# Ferrum browser crawl — element presence and light interaction checks.
# Run from MASTER: BUNDLE_WITH=test bundle exec ruby ../RAILS/tools/crawl_browser.rb

require "optparse"
require "timeout"
require_relative "crawl_support"

SUPPORT = File.expand_path("../../../MASTER/web/script/browser_probe_support.rb", __dir__)
require SUPPORT

def run_checks(browser, checks, label, failures)
  Array(checks).each do |check|
    case check["type"].to_s
    when "selector"
      sel = check["css"] || (check["id"] ? "##{check["id"]}" : nil)
      failures << "#{label}: missing selector #{sel.inspect}" unless sel && BrowserProbeSupport.evaluate(browser, "!!document.querySelector(#{sel.to_json})")
    when "js"
      ok = BrowserProbeSupport.evaluate(browser, "(#{check['expr']})")
      failures << "#{label}: js check failed — #{check['expr']}" unless ok
    when "text_absent"
      body = BrowserProbeSupport.evaluate(browser, "document.body ? document.body.innerText : ''").to_s
      failures << "#{label}: page contains #{check['value'].inspect}" if body.include?(check["value"].to_s)
    else
      failures << "#{label}: unknown browser check type #{check['type'].inspect}"
    end
  rescue StandardError => e
    failures << "#{label}: #{check['type']} — #{e.class}: #{e.message}"
  end
end

def run_master_session(browser, session, label, failures)
  return unless session.is_a?(Hash)

  BrowserProbeSupport.tap_primer(browser) if session["tap_primer"]
  sleep Integer(session.fetch("wait_s", 2))
  if session["tap_primer"]
    snap = BrowserProbeSupport.wait_master_session(browser, timeout_s: Integer(session.fetch("session_timeout_s", 20)))
    failures << "#{label}: primer not fired" unless snap["primerFired"]
    failures << "#{label}: face-session class missing" unless snap["faceSession"]
    failures << "#{label}: MASTER_FACE missing" unless snap["masterFace"] == "object"
  end

  return unless session["ping_chat"]

  chat = BrowserProbeSupport.run_ping_chat(browser, chat_wait_s: Integer(session.fetch("chat_wait_s", 4)))
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
  fatal = BrowserProbeSupport.fatal_js_errors(browser)
  failures << "#{label}: js errors — #{fatal.join('; ')}" unless fatal.empty?
end

options = { public: false, skip_closed: true, force: ENV["PROBE_FORCE_BROWSER"] == "1" }
OptionParser.new do |parser|
  parser.banner = "Usage: crawl_browser.rb [--public] [--strict] [--force]"
  parser.on("--public", "Use HTTPS domains from apps.yml") { options[:public] = true }
  parser.on("--strict", "Fail when target ports are closed") { options[:skip_closed] = false }
  parser.on("--force", "Run even without Chrome (will fail)") { options[:force] = true }
end.parse!

chrome = BrowserProbeSupport.chrome_path
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

manifest = CrawlSupport.load_manifest
apps = CrawlSupport.load_apps_yml
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

begin
  Timeout.timeout(BrowserProbeSupport::MAX_PROBE_SECONDS) do
    browser = BrowserProbeSupport.build_browser(chrome: chrome, pending_connection_errors: false)
    BrowserProbeSupport.install_error_hooks(browser)

    targets.each do |name, port, browser_spec|
      unless options[:public]
        open = CrawlSupport.port_open?("127.0.0.1", port)
        unless open
          if options[:skip_closed]
            skips << "#{name}: port #{port} closed"
            next
          end
          failures << "#{name}: port #{port} closed"
          next
        end
      end

      url = "#{CrawlSupport.base_url(name, port, apps, public: options[:public])}/"
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
  warn "crawl-browser: timeout after #{BrowserProbeSupport::MAX_PROBE_SECONDS}s"
  exit 1
rescue Ferrum::ProcessTimeoutError, Ferrum::DeadBrowserError => e
  warn "crawl-browser: browser unavailable — #{e.class}"
  exit options[:skip_closed] ? 0 : 1
end
