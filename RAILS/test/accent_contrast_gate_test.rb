# frozen_string_literal: true

require "minitest/autorun"
require "yaml"
require "json"
require_relative "../gates/lib/rendered/accent_contrast"

# Nine controls failed their contrast floor before this gate existed, across
# four surfaces axe never visits: the suites run it against each app's home page
# only, and every brgen vertical is a different host. A takeaway button blended
# two competitors' brand hues and measured 2.15; amber's wardrobe swatch put
# body ink on a charcoal garment at 1.21.
#
# The maths is WCAG's and the scope is the interesting half, so both directions
# are pinned: a pair that fails must be reported, and the three kinds of
# background this gate deliberately declines to judge must not be.
class AccentContrastGateTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  # The gate resolves surfaces and ports from the repo root, not from RAILS/.
  REPO = File.expand_path("../..", __dir__)

  def test_the_manifest_registers_it_under_the_rendered_suite
    row = YAML.safe_load_file(File.join(ROOT, "gates/gates.yml")).fetch("accent_contrast")

    assert_equal "lib/rendered/accent_contrast", row.fetch("require")
    assert_equal "Deploy::AccentContrastGate", row.fetch("class")
    assert_equal "rendered_suite", row.fetch("covered_by")
    assert_equal ["browser"], row.fetch("needs")
  end

  # covered_by is a claim that the composite runs this leaf, and the composite
  # keeps its own list. If the two disagree, --all skips the gate as already
  # covered and nothing runs it at all.
  def test_the_suite_runs_the_leaf_it_claims_to_cover
    source = File.read(File.join(ROOT, "gates/lib/rendered_suite.rb"))

    assert_includes source, "rendered/accent_contrast"
    assert_includes source, "AccentContrastGate"
  end

  # The surfaces come from the declared fleet. A list of its own would be a
  # second inventory, and there is no single marketplace subdomain to write down
  # in one: it is markedsplass in Bergen and marketplace in Los Angeles.
  def test_it_reads_the_declared_fleet_rather_than_a_list_of_its_own
    source = File.read(File.join(ROOT, "gates/lib/rendered/accent_contrast.rb"))

    assert_includes source, "GeometryProbe.surfaces"
    refute_match(/\bSURFACES\s*=/, source, "a surface list here would be a second inventory")
  end

  # The instrument, against cases whose answers are known. Injected into a real
  # page so the probe runs against real computed styles rather than a fixture of
  # its own making.
  def test_the_probe_reports_a_failing_pair_and_forgives_the_ambiguous_ones
    skip "no Chrome" unless Deploy::CdpSession.available?
    ports = Deploy::GeometryProbe.app_ports(root: REPO)
    port = ports["brgen"].to_i
    skip "brgen not listening" unless CrawlSupport.port_open?("127.0.0.1", port)

    inject = <<~JS
      (html => {
        const old = document.querySelector("#contrast_probe_fixture");
        if (old) old.remove();
        const host = document.createElement("div");
        host.id = "contrast_probe_fixture";
        host.innerHTML = html;
        document.body.appendChild(host);
        return "ok";
      })
    JS

    Deploy::CdpSession.open(host_map: { "brgen.no" => "127.0.0.1:#{port}" }, timeout: 45) do |cdp|
      cdp.viewport(1440, 900)
      cdp.navigate("http://brgen.no/", settle: 0.8)

      # #777777 on #888888 is 1.09:1 — unreadable, and unambiguously so.
      failing = %(<button class="contrast_bad" style="background:#888888;color:#777777;font-size:16px">x</button>)
      cdp.evaluate("(#{inject})(#{failing.inspect})")
      found = JSON.parse(cdp.evaluate(Deploy::AccentContrastGate::PROBE).to_s)

      assert(found.any? { |f| f["sel"].include?("contrast_bad") },
             "grey on grey at 1.09:1 has to register: #{found}")

      # Black on white is 21:1, the ceiling.
      passing = %(<button class="contrast_good" style="background:#ffffff;color:#000000;font-size:16px">x</button>)
      cdp.evaluate("(#{inject})(#{passing.inspect})")
      good = JSON.parse(cdp.evaluate(Deploy::AccentContrastGate::PROBE).to_s)

      refute(good.any? { |f| f["sel"].include?("contrast_good") },
             "black on white is not a finding: #{good}")

      # The three this gate declines to judge, each with a foreground that would
      # fail if the background were the flat colour it names. A gradient and an
      # image have no single background to measure; a translucent fill
      # composites with whatever is beneath it. Guessing at any of them reports
      # a number nobody can act on.
      {
        "contrast_gradient" => "background:linear-gradient(90deg,#888888,#999999);color:#777777",
        "contrast_image" => %(background-image:url("data:image/gif;base64,R0lGODlhAQABAAAAACw=");background-color:#888888;color:#777777),
        "contrast_alpha" => "background:rgba(136,136,136,0.5);color:#777777",
      }.each do |css_class, style|
        markup = %(<button class="#{css_class}" style="#{style};font-size:16px">x</button>)
        cdp.evaluate("(#{inject})(#{markup.inspect})")
        skipped = JSON.parse(cdp.evaluate(Deploy::AccentContrastGate::PROBE).to_s)

        refute(skipped.any? { |f| f["sel"].include?(css_class) },
               "#{css_class} has no unambiguous background pair, so it is not this gate's finding: #{skipped}")
      end

      cdp.evaluate(%(document.querySelector("#contrast_probe_fixture")?.remove()))
    end
  end

  # Large text has a lower floor, and the gate reads the computed size and
  # weight rather than the selector. 24px normal and 18.66px bold both take 3:1.
  def test_large_text_takes_the_lower_floor
    skip "no Chrome" unless Deploy::CdpSession.available?
    ports = Deploy::GeometryProbe.app_ports(root: REPO)
    port = ports["brgen"].to_i
    skip "brgen not listening" unless CrawlSupport.port_open?("127.0.0.1", port)

    inject = <<~JS
      (html => {
        const old = document.querySelector("#floor_probe_fixture");
        if (old) old.remove();
        const host = document.createElement("div");
        host.id = "floor_probe_fixture";
        host.innerHTML = html;
        document.body.appendChild(host);
        return "ok";
      })
    JS

    # #767676 on #ffffff is 4.54 — over 4.5 either way, so it proves nothing.
    # #949494 on #ffffff is 3.04: under the small-text floor and over the large.
    Deploy::CdpSession.open(host_map: { "brgen.no" => "127.0.0.1:#{port}" }, timeout: 45) do |cdp|
      cdp.viewport(1440, 900)
      cdp.navigate("http://brgen.no/", settle: 0.8)

      small = %(<button class="floor_small" style="background:#ffffff;color:#949494;font-size:16px;font-weight:400">x</button>)
      cdp.evaluate("(#{inject})(#{small.inspect})")
      found = JSON.parse(cdp.evaluate(Deploy::AccentContrastGate::PROBE).to_s)

      assert(found.any? { |f| f["sel"].include?("floor_small") },
             "3.04 at 16px is under the 4.5 floor: #{found}")

      large = %(<button class="floor_large" style="background:#ffffff;color:#949494;font-size:26px;font-weight:400">x</button>)
      cdp.evaluate("(#{inject})(#{large.inspect})")
      big = JSON.parse(cdp.evaluate(Deploy::AccentContrastGate::PROBE).to_s)

      refute(big.any? { |f| f["sel"].include?("floor_large") },
             "3.04 at 26px clears the 3:1 large-text floor: #{big}")

      cdp.evaluate(%(document.querySelector("#floor_probe_fixture")?.remove()))
    end
  end
end
