# frozen_string_literal: true

require "minitest/autorun"
require "yaml"
require_relative "../gates/lib/rendered/webgl_surfaces"

# RAILS/TODO.md section 4: the rendered gates launch Chrome with --disable-gpu,
# which turns WebGL off outright, so MapLibre and the MASTER face both measure
# as an empty canvas. Nothing asserted that a WebGL surface ever drew, and
# nothing could — a gate built on that instrument would have passed or failed
# for reasons that had nothing to do with the map.
class WebglSurfacesGateTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  # The gate resolves paths from the repo root, not from RAILS/.
  REPO = File.expand_path("../..", __dir__)

  def test_the_manifest_registers_it_under_the_rendered_suite
    row = YAML.safe_load_file(File.join(ROOT, "gates/gates.yml")).fetch("webgl_surfaces")

    assert_equal "lib/rendered/webgl_surfaces", row.fetch("require")
    assert_equal "Deploy::WebglSurfacesGate", row.fetch("class")
    assert_equal "rendered_suite", row.fetch("covered_by")
  end

  def test_the_suite_runs_it
    source = File.read(File.join(ROOT, "gates/lib/rendered_suite.rb"))

    assert_includes source, "rendered/webgl_surfaces"
    assert_includes source, "WebglSurfacesGate"
  end

  # The opt-in is per session. Every other gate keeps --disable-gpu, because
  # software GL is slow and rasterises text differently — dropping it globally
  # would change what the layout and CSS gates measure.
  def test_swiftshader_is_opt_in_and_disable_gpu_is_the_default
    source = File.read(File.join(ROOT, "gates/support/cdp_session.rb"))

    assert_match(/@webgl \?.*swiftshader.*disable-gpu/m, source,
                 "the flag has to be a branch, not a replacement")
    assert_includes source, "def initialize(host_map: {}, timeout: DEFAULT_TIMEOUT, webgl: false)"
  end

  # A gate that cannot fail is not a gate. brgen's own front page has no WebGL
  # canvas, so pointed at it this must fail rather than pass quietly.
  def test_it_fails_on_a_surface_that_draws_no_webgl
    skip "no Chrome" unless Deploy::CdpSession.available?
    ports = Deploy::GeometryProbe.app_ports(root: REPO)
    skip "brgen not listening" unless CrawlSupport.port_open?("127.0.0.1", ports["brgen"].to_i)

    gate = Class.new(Deploy::WebglSurfacesGate) do
      const_set(:SURFACES, [ { app: "brgen", host: "brgen.no", path: "/session/new", label: "no_canvas_here" } ].freeze)
      def host_map(ports) = { "brgen.no" => "127.0.0.1:#{ports['brgen']}" }
    end

    result = gate.run

    refute_empty result.failures, "a page with no WebGL canvas has to fail this gate"
    assert_match(/no canvas|no WebGL context/, result.failures.first)
  end
end
