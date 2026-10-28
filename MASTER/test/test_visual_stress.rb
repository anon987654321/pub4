# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require File.expand_path("../checks/support/geometry_probe", __dir__)
require File.expand_path("../checks/support/stress_states", __dir__)
require File.expand_path("../lib/fix/visual_stress", __dir__)

# Stress states: the decisions (which states, how findings are filtered, what
# the council reads) on a scripted CDP double, and the page-side scripts in a
# real headless Chrome on a synthetic page, skipped where Chrome is absent.
class TestVisualStress < Minitest::Test
  SS = Deploy::StressStates
  SM = Deploy::StressMeasure
  VS = Master::Fix::VisualStress
  Surf = Deploy::GeometryProbe::Surface

  def surface(width: 390, height: 844, app: "brgen")
    Surf.new(app:, label: "home", host: nil, path: "/", viewport: width < 500 ? "mobile" : "desktop",
             width:, height:, snapshot: false, port: 1, profile: nil)
  end

  # --- planning ---------------------------------------------------------------

  def test_plan_drops_states_the_page_cannot_show
    plain = SS.plan(surface, { "list" => nil, "support" => {} })
    assert_equal %i[compound narrow320 zoom200 landscape], plain
    full = SS.plan(surface, { "list" => { "count" => 3 }, "support" => { "dark" => true, "reduced_motion" => true } })
    assert_equal SS::ORDER, full
  end

  def test_an_empty_list_container_can_be_emptied_but_not_cloned
    plan = SS.plan(surface, { "list" => { "count" => 0 }, "support" => {} })
    assert_includes plan, :list_empty
    refute_includes plan, :list_200
    refute_includes plan, :list_one
  end

  def test_desktop_skips_landscape_and_a_320_desktop_is_kept
    plan = SS.plan(surface(width: 1280, height: 800), { "support" => {} })
    refute_includes plan, :landscape
    assert_includes plan, :narrow320
    refute_includes SS.plan(surface(width: 320, height: 640), { "support" => {} }), :narrow320
  end

  def test_pick_is_bounded_and_rotates_with_the_pass
    names = SS::ORDER
    assert_equal names.first(4), SS.pick(names, pass: 1, count: 4)
    assert_equal names[4, 4], SS.pick(names, pass: 2, count: 4)
    assert_empty SS.pick(names, pass: 1, count: 0)
    assert_empty SS.pick([], pass: 1, count: 4)
  end

  def test_geometry_of_states
    s = surface
    assert_equal [320, 844], SS.geometry_of(:narrow320, s).then { |g| [g.width, g.height] }
    assert_equal [200, 422], SS.geometry_of(:zoom200, s).then { |g| [g.width, g.height] }
    assert_equal [844, 390], SS.geometry_of(:landscape, s).then { |g| [g.width, g.height] }
    assert_equal({ "prefers-color-scheme" => "dark" }, SS.geometry_of(:dark, s).media)
  end

  def test_off_switch
    ENV["MASTER_VISUAL_STRESS"] = "0"
    assert_empty SS.capture(Object.new, surface, dir: Dir.tmpdir, pass: 1)
  ensure
    ENV["MASTER_VISUAL_STRESS"] = "0"
  end

  # --- findings ---------------------------------------------------------------

  def finding(kind, selector, detail = "d") = { "kind" => kind, "selector" => selector, "detail" => detail }

  def test_only_findings_new_since_resting_are_kept_and_clones_collapse
    base = { "findings" => [finding("text_escapes_container", "main>article:nth-of-type(1)>h2")] }
    now = { "findings" => [
      finding("text_escapes_container", "main>article:nth-of-type(1)>h2"),
      finding("text_escapes_container", "main>article:nth-of-type(9)>h2"),
      finding("overlap", "main>p:nth-of-type(1)"), finding("overlap", "main>p:nth-of-type(2)")
    ] }
    found = SM.new_findings(now, base)
    assert_equal ["overlap"], found.map { |f| f["kind"] }
    assert_equal 1, found.first["similar"]
  end

  # --- evidence text ------------------------------------------------------------

  def capture(state, id, payload) = { surface: Struct.new(:id).new(id), payload: { "composition" => { "state" => state, "base_surface" => "brgen/home/mobile" } }.merge(payload), screenshot: "x.png" }

  def test_context_names_findings_sparse_surfaces_and_the_seed_command
    stress = capture("stress", "brgen/home__stress_compound/mobile",
                     "stress" => { "findings" => [finding("horizontal_overflow", "html", "page scrolls 90px sideways")], "list" => { "selector" => "main>div.feed", "count" => 1 } })
    text = VS.context([stress])
    assert_match(/horizontal_overflow html — page scrolls 90px sideways/, text)
    assert_match(%r{sparse surface brgen/home/mobile: main>div\.feed holds 1 items}, text)
    assert_match(/operator visual seed/, text)
  end

  def test_a_full_list_is_not_sparse
    stress = capture("stress", "a/b__stress_dark/mobile", "stress" => { "findings" => [], "list" => { "selector" => "ul", "count" => 12 } })
    refute_match(/sparse surface/, VS.context([stress]))
    assert_match(/no new layout failures/, VS.context([stress]))
  end

  def test_context_reports_unavailable_engines
    Deploy::CaptureEngine.reset!
    Deploy::CaptureEngine.unavailable["webkit"] = "safaridriver refused"
    assert_match(/engine webkit: unavailable \(safaridriver refused\)/, VS.context([]))
  ensure
    Deploy::CaptureEngine.reset!
  end

  def test_nothing_captured_says_so
    Deploy::CaptureEngine.reset!
    assert_equal "STRESS STATES: none captured", VS.context([])
  end

  # --- the page-side scripts, in a real browser -----------------------------------

  PAGE = <<~HTML
    <!doctype html><html lang="nb"><head><meta charset="utf-8"><style>
    body{font:16px/1.4 Arial;margin:0;padding:12px}
    .card{border:1px solid #333;background:#eee;padding:8px;margin:6px 0;width:300px}
    .title{white-space:nowrap}
    .clip{overflow:hidden;width:120px;height:20px;border:1px solid red;white-space:nowrap}
    .ell{width:40px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
    .a{position:relative;height:30px}.b{position:relative;top:-22px;height:30px}
    </style></head><body><header><nav><a href="#">Hjem</a></nav></header><main>
    <div class="feed" id="feed"><article class="card"><h2 class="title">Første innlegg om Bryggen</h2></article>
    <article class="card"><h2 class="title">Andre innlegg</h2></article><article class="card"><h2 class="title">Tredje innlegg</h2></article></div>
    <div class="clip">Dette er en lang tekst som blir klippet av</div><div class="ell">Veldig lang tekst som kuttes helt ned</div>
    <div class="a">Første linje med tekst</div><div class="b">Andre linje oppå den første</div>
    </main></body></html>
  HTML

  def with_page
    skip "no headless Chrome" unless Deploy::CdpSession.available?
    Dir.mktmpdir("stress-page") do |dir|
      File.write(File.join(dir, "p.html"), PAGE)
      Deploy::CdpSession.open do |cdp|
        cdp.viewport(390, 844, mobile: true)
        cdp.navigate("file://#{File.join(dir, "p.html")}")
        yield cdp
      end
    end
  end

  def test_measure_finds_clipping_truncation_overlap_and_escape
    with_page do |cdp|
      kinds = cdp.evaluate(Deploy::StressMeasure::MEASURE_JS)["findings"].map { |f| f["kind"] }.uniq
      assert_includes kinds, "clipped_text"
      assert_includes kinds, "unreadable_truncation"
      assert_includes kinds, "overlap"
      assert_includes kinds, "text_escapes_container"
    end
  end

  def test_compound_words_change_text_not_structure
    with_page do |cdp|
      before = cdp.evaluate("document.body.querySelectorAll('*').length")
      script = Deploy::StressScripts::COMPOUND_JS.sub("__WORDS__") { SS::COMPOUNDS.to_json }.sub("__LIMIT__", "8")
      result = cdp.evaluate(script)
      assert_operator result["replaced"], :>, 0
      assert_equal before, cdp.evaluate("document.body.querySelectorAll('*').length")
      assert cdp.evaluate("document.body.innerText.includes(#{SS::COMPOUNDS.to_json}[0]) || #{SS::COMPOUNDS.to_json}.some(w => document.body.innerText.includes(w))")
    end
  end

  def test_list_is_found_and_resized_to_empty_one_and_two_hundred
    { 0 => 0, 1 => 1, 200 => 200 }.each do |asked, expected|
      with_page do |cdp|
        assert_equal 3, cdp.evaluate(Deploy::StressScripts::LIST_DETECT_JS)["count"]
        cdp.evaluate(Deploy::StressScripts::LIST_SET_JS.sub("__COUNT__", asked.to_s))
        assert_equal expected, cdp.evaluate("document.querySelectorAll('#feed > article').length")
        assert_equal 0, cdp.evaluate("document.querySelectorAll('[id]:not(#feed)').length")
      end
    end
  end

  def test_capture_states_end_to_end_and_restore_the_viewport
    with_page do |cdp|
      Dir.mktmpdir do |out|
        server_surface = surface
        server_surface.define_singleton_method(:url) { cdp.evaluate("location.href") }
        ENV["MASTER_VISUAL_STRESS"] = "1"
        ENV["MASTER_VISUAL_STRESS_STATES"] = "9"
        caps = SS.capture(cdp, server_surface, dir: out, pass: 1)
        names = caps.map { |c| c[:payload].dig("composition", "stress") }
        assert_includes names, "compound"
        assert_includes names, "list_200"
        assert(caps.all? { |c| File.size(c[:screenshot]).positive? })
        assert_equal 390, cdp.evaluate("screen.width")
      end
    end
  ensure
    ENV["MASTER_VISUAL_STRESS"] = "0"
    ENV.delete("MASTER_VISUAL_STRESS_STATES")
  end
end
