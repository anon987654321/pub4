# frozen_string_literal: true

require "minitest/autorun"
require "yaml"
require "tmpdir"
require "digest"
require "set"
require_relative "checks/method_swap"
require_relative "../../MASTER/checks/lib/rendered/browser_diagnostics"
require_relative "../../MASTER/checks/lib/rendered_suite"

class BrowserDiagnosticsFakeCdp
  attr_reader :visited_url

  def initialize(status: 200, messages: [], http_errors: [], request_errors: [], screenshot_fails: false)
    @status = status
    @messages = messages
    @http_errors = http_errors
    @request_errors = request_errors
    @screenshot_fails = screenshot_fails
  end

  def viewport(_width, _height, mobile: false); end
  def headers(_headers); end
  def clear_cookies; end
  def clear_events; end
  def navigate(url, settle:); @visited_url = url; end
  def status = @status
  def evaluate(script)
    return "Fixture page" if script == "document.title"
    return false if script == "location.protocol === 'chrome-error:'"

    nil
  end
  def console_messages = @messages
  def http_failures = @http_errors
  def request_failures = @request_errors

  def screenshot(path)
    raise Deploy::CdpSession::Error, "fixture screenshot failure" if @screenshot_fails

    File.binwrite(path, "fixture PNG bytes")
    path
  end
end

class BrowserDiagnosticsCheckTest < Minitest::Test
  include MethodSwap

  ROOT = File.expand_path("../..", __dir__)
  SURFACE = Deploy::GeometryProbe::Surface.new(
    app: "brgen", label: "marketplace_listings", host: "markedsplass.brgen.no",
    path: "/listings", viewport: "mobile", width: 390, height: 844,
    port: 38_182, snapshot: false, profile: nil
  )

  def test_check_is_registered_once_and_runs_under_the_rendered_suite
    registry = YAML.safe_load_file(File.join(ROOT, "MASTER", "checks", "checks.yml"))
    row = registry.fetch("browser_diagnostics")

    assert_equal "rendered_suite", row.fetch("covered_by")
    assert_equal "Deploy::BrowserDiagnosticsCheck", row.fetch("class")
    assert_includes Deploy::RenderedSuiteCheck::LEAVES, Deploy::BrowserDiagnosticsCheck
  end

  def test_live_inventory_covers_each_rails_app_and_brgen_vertical_host
    surfaces = Deploy::GeometryProbe.surfaces
    apps = surfaces.map(&:app).uniq

    %w[brgen amber bsdports master].each { |app| assert_includes apps, app }
    hosts = surfaces.filter_map(&:host)
    %w[brgen.no markedsplass.brgen.no dating.brgen.no tv.brgen.no takeaway.brgen.no maps.brgen.no messenger.brgen.no].each do |host|
      assert_includes hosts, host
    end
    assert surfaces.any? { |surface| surface.app == "brgen" && surface.label == "core" && surface.viewport == "mobile" }
    assert surfaces.any? { |surface| surface.app == "brgen" && surface.label == "core" && surface.viewport == "desktop" }
  end

  def test_uncaught_javascript_exceptions_are_blocking
    verdict = Deploy::BrowserDiagnosticsCheck.grade(
      surface: SURFACE, status: 200,
      console_messages: [{ level: "error", source: "exception", text: "Uncaught TypeError", url: "/app.js" }],
      http_failures: [], request_failures: []
    )

    assert_equal 1, verdict[:hard].length
    assert_match(/Uncaught TypeError/, verdict[:hard].first)
    assert_empty verdict[:soft]
  end

  def test_console_errors_and_warnings_are_retained_as_soft_findings_until_strict
    verdict = Deploy::BrowserDiagnosticsCheck.grade(
      surface: SURFACE, status: 200,
      console_messages: [
        { level: "error", source: "console", text: "handled API fallback", url: "/app.js" },
        { level: "warning", source: "console", text: "deprecated option", url: "/app.js" }
      ],
      http_failures: [], request_failures: []
    )

    assert_empty verdict[:hard]
    assert_equal 2, verdict[:soft].length
    assert_match(/console error/, verdict[:soft].first)
    assert_match(/console warning/, verdict[:soft].last)
  end

  def test_document_errors_and_first_party_server_failures_are_blocking
    document = Deploy::BrowserDiagnosticsCheck.grade(
      surface: SURFACE, status: 500, console_messages: [], http_failures: [], request_failures: []
    )
    asset = Deploy::BrowserDiagnosticsCheck.grade(
      surface: SURFACE, status: 200, console_messages: [],
      http_failures: [{ status: 503, url: "http://markedsplass.brgen.no/assets/app.js", resource_type: "Script" }],
      request_failures: []
    )

    assert_includes document[:hard], "document returned HTTP 500"
    assert_match(/first-party resource failed/, asset[:hard].first)
  end

  def test_owned_resources_follow_the_canonical_app_and_vertical_inventories
    amber = Deploy::GeometryProbe::Surface.new(
      app: "amber", label: "home", host: nil, path: "/", viewport: "desktop",
      width: 1440, height: 900, port: 61_352, snapshot: false, profile: nil
    )

    assert Deploy::BrowserDiagnosticsCheck.owned_url?(amber, "https://amberapp.art/assets/application.js")
    assert Deploy::BrowserDiagnosticsCheck.owned_url?(SURFACE, "https://dating.brgen.no/assets/application.js")
    refute Deploy::BrowserDiagnosticsCheck.owned_url?(amber, "https://third-party.invalid/script.js")
  end

  def test_missing_first_party_script_is_blocking_but_missing_image_is_soft
    script = Deploy::BrowserDiagnosticsCheck.grade(
      surface: SURFACE, status: 200, console_messages: [],
      http_failures: [{ status: 404, url: "http://markedsplass.brgen.no/assets/app.js", resource_type: "Script" }],
      request_failures: []
    )

    image = Deploy::BrowserDiagnosticsCheck.grade(
      surface: SURFACE, status: 200, console_messages: [],
      http_failures: [{ status: 404, url: "http://markedsplass.brgen.no/missing.png", resource_type: "Image" }],
      request_failures: []
    )

    assert_match(/first-party resource failed/, script[:hard].first)
    assert_empty script[:soft]
    assert_empty image[:hard]
    assert_match(/HTTP 404/, image[:soft].first)
  end

  def test_failed_first_party_stylesheet_request_is_blocking
    verdict = Deploy::BrowserDiagnosticsCheck.grade(
      surface: SURFACE, status: 200, console_messages: [], http_failures: [],
      request_failures: [{ url: "http://markedsplass.brgen.no/assets/application.css",
                           resource_type: "Stylesheet", error: "net::ERR_CONNECTION_RESET" }]
    )

    assert_match(/first-party executable request failed/, verdict[:hard].first)
  end

  def test_resource_404_is_preserved_as_a_warning_not_silently_dropped
    verdict = Deploy::BrowserDiagnosticsCheck.grade(
      surface: SURFACE, status: 200, console_messages: [],
      http_failures: [{ status: 404, url: "http://markedsplass.brgen.no/missing.png", resource_type: "Image" }],
      request_failures: []
    )

    assert_empty verdict[:hard]
    assert_match(/HTTP 404/, verdict[:soft].first)
  end

  def test_route_capture_writes_a_screenshot_and_manifest_ready_evidence
    Dir.mktmpdir("browser-diagnostics-test") do |dir|
      check = Deploy::BrowserDiagnosticsCheck.new
      check.instance_variable_set(:@result, Deploy::CheckResult.new)
      cdp = BrowserDiagnosticsFakeCdp.new

      row = check.send(:capture_surface, cdp, SURFACE, dir, 0)

      assert_equal "PASS", row.fetch("status")
      assert_equal SURFACE.url, cdp.visited_url
      assert_equal "Fixture page", row.fetch("title")
      assert File.file?(row.fetch("screenshot"))
      assert_equal Digest::SHA256.file(row.fetch("screenshot")).hexdigest, row.fetch("screenshot_sha256")
      assert_equal [], row.fetch("failure_reasons")
    end
  end

  def test_route_capture_fails_when_screenshot_delivery_fails
    Dir.mktmpdir("browser-diagnostics-test") do |dir|
      check = Deploy::BrowserDiagnosticsCheck.new
      check.instance_variable_set(:@result, Deploy::CheckResult.new)
      cdp = BrowserDiagnosticsFakeCdp.new(screenshot_fails: true)

      row = check.send(:capture_surface, cdp, SURFACE, dir, 0)

      assert_equal "FAIL", row.fetch("status")
      assert_match(/screenshot failed/, row.fetch("failure_reasons").join(" "))
      assert_nil row.fetch("screenshot")
    end
  end

  def test_pixel_baselines_are_separate_and_approval_is_explicit
    tracked = SURFACE.dup
    tracked.pixel_snapshot = true
    path = Deploy::BrowserDiagnosticsCheck.visual_baseline_path(tracked)

    assert_match(%r{/MASTER/checks/data/visual_baselines/brgen-marketplace_listings-mobile\.png\z}, path)
    assert_nil Deploy::BrowserDiagnosticsCheck.visual_baseline_path(SURFACE)
    refute Deploy::BrowserDiagnosticsCheck.pixel_baseline_strict?({})
    assert Deploy::BrowserDiagnosticsCheck.pixel_baseline_strict?("CHECK_PIXEL_BASELINE_STRICT" => "true")
    assert_equal 0.01, Deploy::BrowserDiagnosticsCheck.pixel_diff_max_ratio({})
    assert_equal 0.02, Deploy::BrowserDiagnosticsCheck.pixel_diff_max_ratio("CHECK_PIXEL_DIFF_MAX_RATIO" => "0.02")
    %w[-0.1 1.1 NaN Infinity unknown].each do |value|
      assert_raises(ArgumentError, value) do
        Deploy::BrowserDiagnosticsCheck.pixel_diff_max_ratio("CHECK_PIXEL_DIFF_MAX_RATIO" => value)
      end
    end
  end

  def test_pixel_reference_inventory_is_deliberately_smaller_than_structural_inventory
    surfaces = Deploy::GeometryProbe.surfaces
    pixel_surfaces = surfaces.select(&:pixel_snapshot)
    structural_surfaces = surfaces.select(&:snapshot)

    assert_operator pixel_surfaces.size, :>, 0
    assert_operator pixel_surfaces.size, :<, structural_surfaces.size
    # bsdports/home renders the same structure as bsdports/ports_index
    # (snapshot_aliases), so only ports_index carries the pixel baseline.
    %w[master/chat amber/home amber/wardrobe bsdports/ports_index
       brgen/core brgen/marketplace brgen/dating brgen/maps brgen/messenger].each do |key|
      app, label = key.split("/", 2)
      assert pixel_surfaces.any? { |surface| surface.app == app && surface.label == label }, key
    end
  end

  def test_pixel_comparison_is_wired_into_route_evidence_and_never_auto_approves
    source = File.read(File.join(ROOT, "MASTER", "checks", "lib", "rendered", "browser_diagnostics.rb"))
    assert_includes source, "PngDiff.compare"
    refute_includes source, "CHECK_PIXEL_BASELINE_APPROVE"
    assert_includes source, "CHECK_PIXEL_BASELINE_STRICT"
    assert_includes source, "pixel_diff_ratio"
    assert_includes source, "pixel_diff_image"
    refute_includes source, "CHECK_SNAPSHOT_UPDATE"
  end

  def write_rgba(path, width:, height:, changed_pixels: [])
    changed = changed_pixels.to_set
    rgba = (0...(width * height)).flat_map do |index|
      changed.include?(index) ? [255, 255, 255, 255] : [0, 0, 0, 255]
    end
    File.binwrite(path, Deploy::PngDiff.encode_rgba(width, height, rgba.pack("C*")))
  end

  def with_check_env(values)
    previous = values.to_h { |key, _| [key, ENV.key?(key) ? ENV[key] : nil] }
    values.each { |key, value| ENV[key] = value }
    yield
  ensure
    previous.each do |key, value|
      value.nil? ? ENV.delete(key) : ENV[key] = value
    end
  end

  def pixel_evidence(check, baseline:, current:, dir:, surface: SURFACE)
    swap_value(Deploy::BrowserDiagnosticsCheck, :visual_baseline_path, baseline) do
      check.send(:pixel_evidence, surface:, screenshot: current, screenshot_dir: dir,
                screenshot_error: nil)
    end
  end

  def test_pixel_evidence_blocks_a_change_over_budget_and_preserves_heatmap
    Dir.mktmpdir("pixel-evidence") do |dir|
      baseline = File.join(dir, "approved.png")
      current = File.join(dir, "current.png")
      write_rgba(baseline, width: 10, height: 10)
      write_rgba(current, width: 10, height: 10, changed_pixels: [0, 1, 2])

      evidence = with_check_env("CHECK_PIXEL_DIFF_MAX_RATIO" => "0.01") do
        pixel_evidence(Deploy::BrowserDiagnosticsCheck.new, baseline:, current:, dir:)
      end

      assert_equal "REGRESSION", evidence.fetch("status")
      assert_equal 3, evidence.fetch("pixel_diff_count")
      assert_equal 0.03, evidence.fetch("pixel_diff_ratio")
      assert File.file?(evidence.fetch("pixel_diff_image"))
      assert_match(/exceeds 1.0% budget/, evidence.fetch("reason"))
    end
  end

  def test_pixel_evidence_accepts_a_change_within_budget
    Dir.mktmpdir("pixel-evidence") do |dir|
      baseline = File.join(dir, "approved.png")
      current = File.join(dir, "current.png")
      write_rgba(baseline, width: 100, height: 100)
      write_rgba(current, width: 100, height: 100, changed_pixels: [0])

      evidence = pixel_evidence(Deploy::BrowserDiagnosticsCheck.new, baseline:, current:, dir:)

      assert_equal "COMPARED", evidence.fetch("status")
      assert_equal 1, evidence.fetch("pixel_diff_count")
      assert_equal 0.0001, evidence.fetch("pixel_diff_ratio")
    end
  end

  def test_pixel_evidence_reports_dimension_mismatch_as_failure
    Dir.mktmpdir("pixel-evidence") do |dir|
      baseline = File.join(dir, "approved.png")
      current = File.join(dir, "current.png")
      write_rgba(baseline, width: 2, height: 2)
      write_rgba(current, width: 3, height: 2)

      evidence = pixel_evidence(Deploy::BrowserDiagnosticsCheck.new, baseline:, current:, dir:)

      assert_equal "DIMENSION_MISMATCH", evidence.fetch("status")
      assert_nil evidence["pixel_diff_count"]
      assert_match(/dimensions changed/, evidence.fetch("reason"))
    end
  end

  def test_pixel_evidence_never_treats_a_missing_or_corrupt_reference_as_equal
    Dir.mktmpdir("pixel-evidence") do |dir|
      current = File.join(dir, "current.png")
      missing = File.join(dir, "missing.png")
      corrupt = File.join(dir, "corrupt.png")
      write_rgba(current, width: 2, height: 2)
      File.write(corrupt, "not a PNG")

      assert_equal "MISSING", pixel_evidence(Deploy::BrowserDiagnosticsCheck.new,
        baseline: missing, current:, dir:).fetch("status")
      assert_equal "UNSUPPORTED", pixel_evidence(Deploy::BrowserDiagnosticsCheck.new,
        baseline: corrupt, current:, dir:).fetch("status")
    end
  end

  def test_browser_diagnostics_never_writes_or_approves_pixel_baselines
    Dir.mktmpdir("pixel-evidence") do |dir|
      baseline = File.join(dir, "approved.png")
      current = File.join(dir, "current.png")
      write_rgba(current, width: 2, height: 2, changed_pixels: [0])

      evidence = pixel_evidence(Deploy::BrowserDiagnosticsCheck.new, baseline:, current:, dir:)

      assert_equal "MISSING", evidence.fetch("status")
      refute File.exist?(baseline)
      source = File.read(File.join(ROOT, "MASTER", "checks", "lib", "rendered", "browser_diagnostics.rb"))
      refute_includes source, "CHECK_PIXEL_BASELINE_APPROVE"
      assert File.file?(File.join(ROOT, "MASTER", "tools", "approve_visual_baselines.rb"))
    end
  end

  def test_browser_artifacts_are_external_to_the_repository
    source = File.read(File.join(ROOT, "MASTER", "checks", "lib", "rendered", "browser_diagnostics.rb"))
    assert_includes source, "File.join(Dir.tmpdir, \"pub4-browser-diagnostics\")"
    assert_includes source, "cdp.screenshot(path)"
    assert_includes source, "manifest.json"
    refute_match(/Playwright|playwright/i, source)
  end
end
