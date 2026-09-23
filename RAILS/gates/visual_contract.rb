#!/usr/bin/env ruby
# frozen_string_literal: true

# Subprocess gates are started with system() and do not inherit runner.rb's
# Encoding.default_external; see the same require in release.rb.
require_relative "../../OPENBSD/lib/utf8"
require "json"
require "digest"
require_relative "support/cdp_session"
require_relative "support/geometry_probe"
require "fileutils"
require "uri"
require "time"
require "yaml"

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
  ACCESSIBILITY_PROBE = <<~JS
    return [
      ...[...document.querySelectorAll('img:not([alt])')].map(() => 'image_without_alt'),
      ...[...document.querySelectorAll('button')].filter((el) => !(el.innerText.trim() || el.getAttribute('aria-label'))).map(() => 'button_without_name'),
      ...(document.querySelectorAll('h1').length !== 1 ? ['heading_one_count'] : []),
      ...[...document.querySelectorAll('input:not([type=hidden]), textarea, select')].filter((el) => !(el.labels?.length || el.getAttribute('aria-label'))).map(() => 'field_without_label')
    ];
  JS

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

  SURFACES = File.expand_path("data/geometry_surfaces.yml", __dir__)

  module_function

  def volatile_selectors = Array(YAML.safe_load_file(SURFACES)["volatile_selectors"])

  # One stylesheet appended after load, so every match is hidden however late
  # it renders; visibility rather than display, so nothing reflows around it.
  def mask_script(selectors = volatile_selectors)
    rule = "#{selectors.join(", ")} { visibility: hidden !important; }"
    "const s = document.createElement('style'); s.textContent = #{JSON.generate(rule)}; document.head.appendChild(s);"
  end

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
    driver.execute_script(ACCESSIBILITY_PROBE)
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

  def capture(base:, app:, output: File.expand_path("../visual_contract", __dir__))
    FileUtils.mkdir_p(output)
    results = []

    CdpSession.open(timeout: Integer(ENV.fetch("GATE_BROWSER_TIMEOUT", "20"))) do |cdp|
      cdp.on_new_document(GeometryProbe::DETERMINISM)
      cdp.headers(GeometryProbe::PROBE_HEADERS)

      matrix(app).each do |cell|
        width, height = cell[:dimensions]
        cdp.viewport(width, height, mobile: width < 500)
        cdp.clear_cookies
        cdp.navigate(URI.join(base, cell[:route]).to_s, settle: 0.15)

        slug = [cell[:app], cell[:state], cell[:viewport]].join("-")
        screenshot = File.join(output, "#{slug}.png")
        baseline_bytes = File.binread(screenshot) if File.file?(screenshot)
        cdp.evaluate(mask_script)
        cdp.screenshot(screenshot)

        diff = baseline_bytes ? pixel_diff(
          baseline_bytes:,
          screenshot_path: screenshot,
          diff_path: File.join(output, "#{slug}-diff.png"),
        ) : { pixel_diff_count: nil, pixel_diff_ratio: nil, pixel_diff_image: nil }

        results << {
          app: cell[:app], state: cell[:state], viewport: cell[:viewport], route: cell[:route],
          status: cdp.status,
          title: cdp.evaluate("document.title"),
          screenshot: screenshot,
          screenshot_sha256: Digest::SHA256.file(screenshot).hexdigest,
          **diff,
          console_errors: cdp.console_errors,
          accessibility_violations: cdp.evaluate(ACCESSIBILITY_PROBE),
          lenses: LENSES,
        }
      end
    end

    results
  rescue CdpSession::Error, SystemCallError => e
    raise CannotMeasure, "CDP capture failed (#{e.class}: #{e.message})"
  end

end

# The tests require this file to exercise grade, identical_captures and
# validate! without a browser. Only the script run navigates anything — and
# only the script run may reach the `exit` below, which under `require` would
# take the requiring process down with it.
return unless $PROGRAM_NAME == __FILE__

rows = VisualContractGate.validate!
unless ARGV.delete("--capture")
  # Exit 3, not 0. Without --capture this run reads the matrix declaration and
  # navigates nothing: no screenshot, no status, no drift. It reported that as a
  # clean pass under a runner line reading "Chrome present — 1 browser-backed
  # gate(s) could measure", which is the false green this gate's own
  # identical_captures check exists to catch one level down.
  #
  # validate! above is still a real check and still exits 1 when the matrix is
  # malformed; 3 is the runner's code for "I could not measure", which never
  # blocks by default and is counted apart from the passes. No line here starts
  # with "ok", because a reader skimming for it would take a declaration for a
  # measurement.
  warn "visual_contract: matrix declares #{rows.length} cells across #{VisualContractGate::ROUTES.length} apps; " \
       "none was captured (VISUAL_CAPTURE=1 with a booted app captures)"
  warn "visual_contract: nothing measured, so nothing is claimed"
  exit 3
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
# capture measured (TODO.md: rails_gates_not_wired —
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

# The other half of the same question, and the half that was missing: a run can
# navigate every cell and still measure nothing by fetching the same page for
# each of them. See VisualContractGate.identical_captures for what the
# committed manifests recorded.
duplicates = VisualContractGate.identical_captures(results)
unless duplicates.empty?
  warn "visual_contract: states that captured an identical page from different routes —"
  duplicates.each do |(viewport, sha), rows|
    cells = rows.map { |row| "#{row[:state]}(#{row[:route]})" }.join(" ")
    warn "  #{viewport} #{sha[0, 8]}: #{cells}"
  end
  warn "visual_contract: those cells measured nothing of their own"
  exit 1
end

VisualContractGate.fragment_only_captures(results).each do |(viewport, sha), rows|
  cells = rows.map { |row| row[:state] }.join(", ")
  document = rows.first[:route].to_s.split("#").first
  warn "visual_contract: #{viewport} #{sha[0, 8]} — #{cells} are one document (#{document}); " \
       "their counts are that page measured #{rows.length}x"
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
