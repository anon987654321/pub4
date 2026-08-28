#!/usr/bin/env ruby
# frozen_string_literal: true
# frozen_string_literal: true
# Screenshot-first calibration loop (design_rules.yml automated_iteration).
# Captures primer + post-tap session at desktop/mobile, writes manifest + latest symlink.
# Prereq: MASTER web on loopback (53187). Sync CSS first:
#   bundle exec rails assets:precompile   # updates public/assets/.manifest.json
#   bundle exec rails server -p 53187 -b 127.0.0.1

require "fileutils"
require "json"
require "optparse"

URL = "http://127.0.0.1:53187/"
OUT_ROOT = File.expand_path("../../reports/screenshots/calibration", __dir__)
CHROME_PATHS = [
  ENV["CHROME_PATH"],
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
  "/Applications/Chromium.app/Contents/MacOS/Chromium",
  "/usr/local/bin/chromium",
  "/usr/local/bin/chrome",
].compact.freeze

options = { url: URL, out: OUT_ROOT, wait: 2.0, tap_wait: 8.0 }
OptionParser.new do |opts|
  opts.banner = "usage: screenshot_calibrate.rb [--url URL] [--out DIR]"
  opts.on("--url URL") { |v| options[:url] = v }
  opts.on("--out DIR") { |v| options[:out] = File.expand_path(v) }
  opts.on("--wait SEC", Float) { |v| options[:wait] = v }
  opts.on("--tap-wait SEC", Float) { |v| options[:tap_wait] = v }
end.parse!

chrome = CHROME_PATHS.find { |path| File.executable?(path) }
abort("screenshot_calibrate: no Chrome executable") unless chrome

require "ferrum"

VIEWPORTS = {
  "desktop" => [1440, 900],
  "mobile" => [390, 844],
}.freeze

FileUtils.mkdir_p(options[:out])
stamp = Time.now.utc.strftime("%Y%m%dT%H%M%SZ")
run_dir = File.join(options[:out], stamp)
FileUtils.mkdir_p(run_dir)

browser = Ferrum::Browser.new(
  browser_path: chrome,
  headless: "new",
  timeout: 60,
  process_timeout: 45,
  pending_connection_errors: false,
  browser_options: {
    "no-sandbox" => nil,
    "disable-dev-shm-usage" => nil,
    "disable-gpu" => nil,
    "enable-webgl" => nil,
    "use-gl" => "swiftshader",
    "enable-unsafe-swiftshader" => nil,
    "ignore-certificate-errors" => nil,
    "remote-allow-origins" => "*",
  },
)

manifest = { generated_at: Time.now.utc.iso8601, url: options[:url], shots: [] }

def capture!(browser, path, label, manifest, viewport: nil)
  if viewport
    w, h = viewport
    browser.resize(width: w, height: h)
    sleep 0.2
  end
  browser.screenshot(path:, full: false)
  manifest[:shots] << { label:, path:, viewport: viewport || browser.evaluate("[window.innerWidth, window.innerHeight]") }
  puts "ok: #{label} -> #{path}"
end

begin
  browser.go_to(options[:url])
  sleep options[:wait]

  VIEWPORTS.each do |name, dims|
    capture!(browser, File.join(run_dir, "01-primer-#{name}.png"), "primer-#{name}", manifest, viewport: dims)
  end

  primer = browser.at_css("#primer")
  if primer
    primer.click
  else
    browser.mouse.click(x: 720, y: 450)
  end
  sleep options[:tap_wait]

  state = browser.evaluate(<<~JS)
    ({
      primerFired: !!window._primerFired,
      primerGone: !document.getElementById('primer'),
      faceSession: document.body.classList.contains('face-session'),
      zshLive: document.getElementById('zsh')?.classList.contains('live'),
      faceType: typeof window.MASTER_FACE
    })
  JS

  VIEWPORTS.each do |name, dims|
    capture!(browser, File.join(run_dir, "02-session-#{name}.png"), "session-#{name}", manifest, viewport: dims)
  end

  manifest[:state] = state
  manifest[:stylecoach] = []

  # StyleCoach heuristics from project_context.yml
  checks = []
  checks << ["primer-consent", "12px", "16px", "Consent copy below 16px body minimum on mobile"] if browser.at_css("#primer .primer-consent")
  checks << ["chat-log", "11.5px", "12px", "Chat log microtype below readable HUD floor"] if browser.at_css("#chat-log")
  checks << ["provider-chip", "9px", "10px", "Provider chip at HUD micro scale — acceptable if non-interactive"] if browser.at_css(".provider-chip")

  manifest[:stylecoach] = checks.map { |element, current, suggested, reason| { element:, current:, suggested:, reason: } }

  manifest_path = File.join(run_dir, "manifest.json")
  File.write(manifest_path, JSON.pretty_generate(manifest) + "\n")
  latest = File.join(options[:out], "latest")
  FileUtils.rm_f(latest)
  # Relative, because latest and run_dir are always siblings under --out.
  # An absolute link is the path of the checkout that happened to render it,
  # so it resolves into that tree from every other clone and worktree.
  FileUtils.ln_s(File.basename(run_dir), latest)
  puts "ok: manifest -> #{manifest_path}"
  puts "state: #{state.inspect}"
rescue StandardError => e
  warn "FAIL screenshot_calibrate: #{e.class}: #{e.message}"
  exit 1
ensure
  browser&.quit
end
