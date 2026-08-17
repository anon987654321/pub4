#!/usr/bin/env ruby
# frozen_string_literal: true

# Subprocess gates are started with system() and do not inherit runner.rb's
# Encoding.default_external; see the same require in release.rb.
require_relative "../../OPENBSD/lib/utf8"
require "json"
require "digest"
require "fileutils"
require "uri"
require "time"

# Drift past which a run blocks rather than reports. VISUAL_DRIFT_MAX_RATIO
# overrides it; nothing set it before, so drift_max was nil and drift was purely
# informational — the ratio was computed on every run and could never fail one.
#
# Deliberately loose. The baseline is the previous run's screenshot, so any
# intended change drifts once and then re-baselines to zero on the next run; a
# tight ceiling would fire on every deliberate tweak and teach people to ignore
# it. A quarter of the viewport changing is not a tweak — it is a stylesheet
# that failed to load or a grid that collapsed, which is the class of failure
# worth blocking on and the one a geometry gate can miss entirely.
DEFAULT_DRIFT_MAX_RATIO = "0.25"

# Seeded screenshot contract for every product grammar and failure state. Run
# under any Rails app bundle:
#   bundle exec ruby ../visual_contract_gate.rb --capture --base http://127.0.0.1:3000 --app brgen
module VisualContractGate
  VIEWPORTS = {
    desktop: [1440, 900],
    compact: [1024, 768],
    mobile: [390, 844],
  }.freeze

  ROUTES = {
    brgen: {
      public: "/", sign_in: "/session/new", empty: "/?q=visual-contract-no-match",
      results: "/?sort=latest", error: "/404-visual-contract", offline: "/offline",
      # Marketplace vertical (Host markedsplass.* in capture when available)
      marketplace: "/", marketplace_sign_in: "/session/new",
    },
    amber: {
      public: "/", sign_in: "/session/new", wardrobe: "/items", item: "/items/1",
      outfit: "/outfits/1", upload: "/items/new", ai_result: "/ai/suggest_outfits",
      empty: "/items?q=visual-contract-no-match", error: "/404-visual-contract", offline: "/offline",
    },
    bsdports: {
      public: "/", empty: "/ports?q=visual-contract-no-match", results: "/ports?q=git",
      detail: "/ports/1", advisory: "/ports/1#cves-security-advisories",
      dependency: "/ports/1#this-package-requires", error: "/404-visual-contract", offline: "/offline",
    },
  }.freeze

  LENSES = %w[task_completion accessibility editorial_character system_trust first_use].freeze

  module_function

  def matrix(app)
    ROUTES.fetch(app.to_sym).flat_map do |state, route|
      VIEWPORTS.map { |viewport, dimensions| { app: app.to_sym, state:, route:, viewport:, dimensions: } }
    end
  end

  def validate!
    raise "visual crawl needs five critique lenses" unless LENSES.length == 5
    raise "missing empty/error/offline contract" unless ROUTES.values.all? { |routes| %i[empty error offline].all? { |state| routes.key?(state) } }
    rows = ROUTES.keys.flat_map { |app| matrix(app) }
    keys = rows.map { |row| row.values_at(:app, :state, :viewport) }
    raise "duplicate visual crawl cell" unless keys.uniq.length == keys.length
    rows
  end

  def accessibility_violations(driver)
    driver.execute_script(<<~JS)
      return [
        ...[...document.querySelectorAll('img:not([alt])')].map(() => 'image_without_alt'),
        ...[...document.querySelectorAll('button')].filter((el) => !(el.innerText.trim() || el.getAttribute('aria-label'))).map(() => 'button_without_name'),
        ...(document.querySelectorAll('h1').length !== 1 ? ['heading_one_count'] : []),
        ...[...document.querySelectorAll('input:not([type=hidden]), textarea, select')].filter((el) => !(el.labels?.length || el.getAttribute('aria-label'))).map(() => 'field_without_label')
      ];
    JS
  end

  # Diffs the prior screenshot at the same path (rolling baseline from the last
  # capture run) against the freshly captured one. Same-dimension mismatch only:
  # a viewport/layout size change isn't a pixel regression, it's a new baseline.
  def pixel_diff(baseline_bytes:, screenshot_path:, diff_path:)
    require "chunky_png"
    baseline = ChunkyPNG::Image.from_blob(baseline_bytes)
    current = ChunkyPNG::Image.from_file(screenshot_path)
    return { pixel_diff_count: nil, pixel_diff_ratio: nil, pixel_diff_image: nil } unless baseline.width == current.width && baseline.height == current.height

    baseline_pixels = baseline.pixels
    current_pixels = current.pixels
    diff_count = baseline_pixels.each_index.count { |i| baseline_pixels[i] != current_pixels[i] }
    if diff_count.positive?
      pixels = Array.new(baseline_pixels.length) do |i|
        baseline_pixels[i] == current_pixels[i] ? ChunkyPNG::Color::TRANSPARENT : ChunkyPNG::Color.rgba(255, 0, 64, 255)
      end
      ChunkyPNG::Image.new(current.width, current.height, pixels).save(diff_path)
    end
    { pixel_diff_count: diff_count, pixel_diff_ratio: (diff_count.to_f / baseline_pixels.length).round(6), pixel_diff_image: diff_count.positive? ? diff_path : nil }
  end

  # Classic Selenium `driver.manage.logs` was removed from selenium-webdriver's
  # Ruby bindings; newer versions only expose console output via BiDi. Degrade to
  # an empty list rather than crash the whole capture when it's unavailable.
  def browser_console_errors(driver)
    return [] unless driver.manage.respond_to?(:logs)

    driver.manage.logs.get(:browser).select { |log| log.level == "SEVERE" }.map(&:message)
  end

  # Grades a capture. Extracted from the script body so the three severities are
  # assertable without Chrome and a running app — the reason the old version
  # never failed on anything was that nothing could see what it decided.
  #
  #   hard  — blocks. A contract route answering 5xx, or drift past an explicit
  #           VISUAL_DRIFT_MAX_RATIO.
  #   soft  — real defects whose live counts have never been measured from this
  #           tree, so they block only under strict:. Same shape as
  #           GateResult's soft failures.
  #   drift — reported always; a rolling baseline makes any intended change drift.
  def grade(results, strict: false, drift_max: nil)
    hard = []
    soft = []

    results.each do |row|
      status = row[:status].to_i
      next if status.zero? # navigation timing unavailable — nothing measured
      next if row[:state].to_s == "error" && status == 404 # this cell asks for a 404
      next if status < 500

      hard << "#{row[:state]}/#{row[:viewport]} #{row[:route]} returned #{status}"
    end

    a11y = results.sum { |row| row[:accessibility_violations].to_a.length }
    console = results.sum { |row| row[:console_errors].to_a.length }
    soft << "#{a11y} accessibility violation(s)" if a11y.positive?
    soft << "#{console} severe console error(s)" if console.positive?

    drifted = results.select { |row| row[:pixel_diff_count].to_i.positive? }
    worst = drifted.map { |row| row[:pixel_diff_ratio].to_f }.max || 0.0
    if drift_max && worst > drift_max
      hard << "pixel drift ratio #{worst.round(6)} exceeds VISUAL_DRIFT_MAX_RATIO=#{drift_max}"
    end

    hard += soft.map { |message| "[strict] #{message}" } if strict

    {
      hard:, soft: strict ? [] : soft,
      drift: { states: drifted.length, pixels: drifted.sum { |row| row[:pixel_diff_count].to_i }, worst_ratio: worst },
    }
  end

  # Raised, not returned, so the caller decides the exit code. A missing driver
  # gem or an unreachable Chrome is a precondition this machine does not meet —
  # not a verdict about the tree — and it used to surface as an uncaught
  # LoadError, which exits 1 and reads as FAILED. Wrong in both directions: it
  # blocks on nothing, and it hides that nothing was measured.
  CannotMeasure = Class.new(StandardError)

  def capture(base:, app:, output: File.expand_path("../visual_contract", __dir__))
    begin
      require "selenium-webdriver"
    rescue LoadError => e
      raise CannotMeasure, "selenium-webdriver is not installed (#{e.message})"
    end
    FileUtils.mkdir_p(output)
    options = Selenium::WebDriver::Chrome::Options.new
    options.add_argument("--headless=new")
    options.add_argument("--no-sandbox")
    options.add_argument("--disable-dev-shm-usage")
    options.add_option("goog:loggingPrefs", { browser: "ALL" })
    driver = begin
      Selenium::WebDriver.for(:chrome, options:)
    rescue StandardError => e
      # No Chrome on PATH, or a driver that will not start. Same category as the
      # gem being absent: a precondition, not a finding.
      raise CannotMeasure, "could not start Chrome (#{e.class}: #{e.message})"
    end
    matrix(app).map do |cell|
      width, height = cell[:dimensions]
      driver.manage.window.resize_to(width, height)
      driver.navigate.to(URI.join(base, cell[:route]).to_s)
      sleep 0.15
      slug = [cell[:app], cell[:state], cell[:viewport]].join("-")
      screenshot = File.join(output, "#{slug}.png")
      baseline_bytes = File.binread(screenshot) if File.file?(screenshot)
      driver.save_screenshot(screenshot)
      diff = baseline_bytes ? pixel_diff(baseline_bytes:, screenshot_path: screenshot, diff_path: File.join(output, "#{slug}-diff.png")) : { pixel_diff_count: nil, pixel_diff_ratio: nil, pixel_diff_image: nil }
      {
        app: cell[:app], state: cell[:state], viewport: cell[:viewport], route: cell[:route],
        status: driver.execute_script("return performance.getEntriesByType('navigation')[0]?.responseStatus || null"),
        title: driver.title, screenshot: screenshot,
        screenshot_sha256: Digest::SHA256.file(screenshot).hexdigest,
        **diff,
        console_errors: browser_console_errors(driver),
        accessibility_violations: accessibility_violations(driver), lenses: LENSES
      }
    end
  ensure
    driver&.quit
  end
end

rows = VisualContractGate.validate!
unless ARGV.delete("--capture")
  puts "ok: #{rows.length} seeded visual contract cells across #{VisualContractGate::ROUTES.length} apps"
  return
end

app_i = ARGV.index("--app")
base_i = ARGV.index("--base")
app = (app_i && ARGV[app_i + 1]) || abort("--app brgen|amber|bsdports required")
base = (base_i && ARGV[base_i + 1]) || abort("--base URL required")
results = begin
  VisualContractGate.capture(base:, app:)
rescue VisualContractGate::CannotMeasure => e
  warn "visual_contract: #{e.message}"
  warn "visual_contract: nothing measured, so nothing is claimed"
  exit 3
end
path = File.expand_path("../visual_contract/#{app}-manifest.json", __dir__)
File.write(path, JSON.pretty_generate(generated_at: Time.now.utc.iso8601, results:) + "\n")

# This used to end at `puts "ok: captured …"` with exit 0 no matter what the
# capture measured (OPENBSD/data/debt.yml: rails_gates_not_wired —
# "visual_contract_gate computes drift/a11y counts and never exits non-zero").
# A gate that sees a 500 on the sign-in page and reports "ok" is a report.
verdict = VisualContractGate.grade(
  results,
  strict: %w[1 true yes on].include?(ENV["VISUAL_STRICT"].to_s.strip.downcase),
  drift_max: Float(ENV.fetch("VISUAL_DRIFT_MAX_RATIO", DEFAULT_DRIFT_MAX_RATIO))
)

# Nothing navigated, so nothing was compared. `grade` already skips a row whose
# status is 0 as "navigation timing unavailable", and if every row is that row
# the run has no opinion about the tree: no 5xx found because no page loaded, no
# drift found because no pixels were diffed. Exiting 0 here reported that as a
# clean pass, and Chrome-absent is the normal state on a machine that has not
# booted the apps. 3 is the runner's code for inconclusive.
measured = results.count { |row| row[:status].to_i.positive? }
if measured.zero?
  warn "visual_contract: no state navigated (#{results.length} attempted) — Chrome and a booted app are required"
  warn "visual_contract: nothing measured, so nothing is claimed"
  exit 3
end

drift = verdict[:drift]
if drift[:states].positive?
  warn "Drift: #{drift[:states]} state(s), #{drift[:pixels]} px total, worst ratio #{drift[:worst_ratio].round(6)}"
end
verdict[:soft].each { |message| warn "Warning: #{message} (VISUAL_STRICT=1 makes this blocking)" }

unless verdict[:hard].empty?
  warn "Failures:"
  verdict[:hard].each { |message| warn "  - #{message}" }
  exit 1
end

puts "ok: captured #{results.length} visual states -> #{path}"
