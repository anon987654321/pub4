# frozen_string_literal: true

require "minitest/autorun"
require "yaml"
require "tmpdir"
require "digest"
require_relative "../../MASTER/gates/lib/rendered/browser_diagnostics"
require_relative "../../MASTER/gates/lib/rendered_suite"

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

class BrowserDiagnosticsGateTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  SURFACE = Deploy::GeometryProbe::Surface.new(
    app: "brgen", label: "marketplace_listings", host: "markedsplass.brgen.no",
    path: "/listings", viewport: "mobile", width: 390, height: 844,
    port: 38_182, snapshot: false, profile: nil
  )

  def test_gate_is_registered_once_and_runs_under_the_rendered_suite
    registry = YAML.safe_load_file(File.join(ROOT, "MASTER", "gates", "gates.yml"))
    row = registry.fetch("browser_diagnostics")

    assert_equal "rendered_suite", row.fetch("covered_by")
    assert_equal "Deploy::BrowserDiagnosticsGate", row.fetch("class")
    assert_includes Deploy::RenderedSuiteGate::LEAVES, Deploy::BrowserDiagnosticsGate
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
    verdict = Deploy::BrowserDiagnosticsGate.grade(
      surface: SURFACE, status: 200,
      console_messages: [{ level: "error", source: "exception", text: "Uncaught TypeError", url: "/app.js" }],
      http_failures: [], request_failures: []
    )

    assert_equal 1, verdict[:hard].length
    assert_match(/Uncaught TypeError/, verdict[:hard].first)
    assert_empty verdict[:soft]
  end

  def test_console_errors_and_warnings_are_retained_as_soft_findings_until_strict
    verdict = Deploy::BrowserDiagnosticsGate.grade(
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
    document = Deploy::BrowserDiagnosticsGate.grade(
      surface: SURFACE, status: 500, console_messages: [], http_failures: [], request_failures: []
    )
    asset = Deploy::BrowserDiagnosticsGate.grade(
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

    assert Deploy::BrowserDiagnosticsGate.owned_url?(amber, "https://amberapp.art/assets/application.js")
    assert Deploy::BrowserDiagnosticsGate.owned_url?(SURFACE, "https://dating.brgen.no/assets/application.js")
    refute Deploy::BrowserDiagnosticsGate.owned_url?(amber, "https://third-party.invalid/script.js")
  end

  def test_missing_first_party_script_is_blocking_but_missing_image_is_soft
    script = Deploy::BrowserDiagnosticsGate.grade(
      surface: SURFACE, status: 200, console_messages: [],
      http_failures: [{ status: 404, url: "http://markedsplass.brgen.no/assets/app.js", resource_type: "Script" }],
      request_failures: []
    )

    image = Deploy::BrowserDiagnosticsGate.grade(
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
    verdict = Deploy::BrowserDiagnosticsGate.grade(
      surface: SURFACE, status: 200, console_messages: [], http_failures: [],
      request_failures: [{ url: "http://markedsplass.brgen.no/assets/application.css",
                           resource_type: "Stylesheet", error: "net::ERR_CONNECTION_RESET" }]
    )

    assert_match(/first-party executable request failed/, verdict[:hard].first)
  end

  def test_resource_404_is_preserved_as_a_warning_not_silently_dropped
    verdict = Deploy::BrowserDiagnosticsGate.grade(
      surface: SURFACE, status: 200, console_messages: [],
      http_failures: [{ status: 404, url: "http://markedsplass.brgen.no/missing.png", resource_type: "Image" }],
      request_failures: []
    )

    assert_empty verdict[:hard]
    assert_match(/HTTP 404/, verdict[:soft].first)
  end

  def test_route_capture_writes_a_screenshot_and_manifest_ready_evidence
    Dir.mktmpdir("browser-diagnostics-test") do |dir|
      gate = Deploy::BrowserDiagnosticsGate.new
      gate.instance_variable_set(:@result, Deploy::GateResult.new)
      cdp = BrowserDiagnosticsFakeCdp.new

      row = gate.send(:capture_surface, cdp, SURFACE, dir, 0)

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
      gate = Deploy::BrowserDiagnosticsGate.new
      gate.instance_variable_set(:@result, Deploy::GateResult.new)
      cdp = BrowserDiagnosticsFakeCdp.new(screenshot_fails: true)

      row = gate.send(:capture_surface, cdp, SURFACE, dir, 0)

      assert_equal "FAIL", row.fetch("status")
      assert_match(/screenshot failed/, row.fetch("failure_reasons").join(" "))
      assert_nil row.fetch("screenshot")
    end
  end

  def test_browser_artifacts_are_external_to_the_repository_and_baselines_are_not_updated
    source = File.read(File.join(ROOT, "MASTER", "gates", "lib", "rendered", "browser_diagnostics.rb"))
    assert_includes source, "File.join(Dir.tmpdir, \"pub4-browser-diagnostics\")"
    assert_includes source, "cdp.screenshot(path)"
    assert_includes source, "manifest.json"
    refute_includes source, "GATE_SNAPSHOT_UPDATE"
    refute_match(/Playwright|playwright/i, source)
  end
end
