# frozen_string_literal: true

require "minitest/autorun"
require "yaml"
require_relative "../../MASTER/gates/lib/rendered/browser_diagnostics"
require_relative "../../MASTER/gates/lib/rendered_suite"

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

  def test_uncaught_exceptions_and_console_errors_are_blocking
    verdict = Deploy::BrowserDiagnosticsGate.grade(
      surface: SURFACE, status: 200,
      console_messages: [{ level: "error", source: "exception", text: "Uncaught TypeError", url: "/app.js" }],
      http_failures: [], request_failures: []
    )

    assert_equal 1, verdict[:hard].length
    assert_match(/Uncaught TypeError/, verdict[:hard].first)
    assert_empty verdict[:soft]
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

  def test_resource_404_is_preserved_as_a_warning_not_silently_dropped
    verdict = Deploy::BrowserDiagnosticsGate.grade(
      surface: SURFACE, status: 200, console_messages: [],
      http_failures: [{ status: 404, url: "http://markedsplass.brgen.no/missing.png", resource_type: "Image" }],
      request_failures: []
    )

    assert_empty verdict[:hard]
    assert_match(/HTTP 404/, verdict[:soft].first)
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
