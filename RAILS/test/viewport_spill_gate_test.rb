# frozen_string_literal: true

require "minitest/autorun"
require "yaml"
require "json"
require_relative "../gates/lib/rendered/viewport_spill"

# Six surfaces hung off the right edge of a 390px phone before this gate
# existed, and no source read would have found any of them: the causes were a
# percentage max-width that ignores margins, a fieldset's min-content floor, an
# untemplated grid column, a bleed cancelling a pad that was not applied, and a
# flex item sized to its content. Only a browser can say where an element's
# right edge lands.
class ViewportSpillGateTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  # The gate resolves app ports from the repo root, not from RAILS/.
  REPO = File.expand_path("../..", __dir__)

  def test_the_manifest_registers_it_under_the_rendered_suite
    row = YAML.safe_load_file(File.join(ROOT, "gates/gates.yml")).fetch("viewport_spill")

    assert_equal "lib/rendered/viewport_spill", row.fetch("require")
    assert_equal "Deploy::ViewportSpillGate", row.fetch("class")
    assert_equal "rendered_suite", row.fetch("covered_by")
  end

  def test_the_suite_runs_it
    source = File.read(File.join(ROOT, "gates/lib/rendered_suite.rb"))

    assert_includes source, "rendered/viewport_spill"
    assert_includes source, "ViewportSpillGate"
  end

  def test_it_measures_the_phone_width_it_claims_to
    assert_equal 390, Deploy::ViewportSpillGate::WIDTH
  end

  # The instrument, checked against a case whose answer is known: an element
  # explicitly wider than the viewport must be reported, and the same element
  # inside a sideways scroller must not — a chip rail is meant to run past the
  # edge, and a gate that cannot tell the two apart would fail every surface.
  def test_the_probe_sees_a_spill_and_forgives_a_scroller
    skip "no Chrome" unless Deploy::CdpSession.available?
    ports = Deploy::GeometryProbe.app_ports(root: REPO)
    port = ports["brgen"].to_i
    skip "brgen not listening" unless CrawlSupport.port_open?("127.0.0.1", port)

    inject = <<~JS
      (html => {
        const host = document.createElement("div");
        host.id = "spill_probe_fixture";
        host.innerHTML = html;
        document.body.appendChild(host);
        return "ok";
      })
    JS

    Deploy::CdpSession.open(host_map: { "brgen.no" => "127.0.0.1:#{port}" }, timeout: 45) do |cdp|
      cdp.viewport(Deploy::ViewportSpillGate::WIDTH, Deploy::ViewportSpillGate::HEIGHT, mobile: true)
      cdp.navigate("http://brgen.no/session/new", settle: 0.8)

      bare = %(<div class="spill_wide" style="width:900px;height:8px"></div>)
      cdp.evaluate("(#{inject})(#{bare.inspect})")
      found = JSON.parse(cdp.evaluate(Deploy::ViewportSpillGate::PROBE).to_s)

      assert(found.any? { |f| f.include?("spill_wide") }, "a 900px box on a 390px screen has to register: #{found}")

      scrolled = %(<div style="overflow-x:auto;width:100%">) +
                 %(<div class="spill_rail" style="width:900px;height:8px"></div></div>)
      cdp.evaluate(%(document.querySelector("#spill_probe_fixture").remove()))
      cdp.evaluate("(#{inject})(#{scrolled.inspect})")
      rail = JSON.parse(cdp.evaluate(Deploy::ViewportSpillGate::PROBE).to_s)

      refute(rail.any? { |f| f.include?("spill_rail") }, "content inside a sideways scroller is not a spill: #{rail}")
    end
  end
end
