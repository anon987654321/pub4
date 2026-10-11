# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require File.expand_path("../gates/support/geometry_probe", __dir__)
require File.expand_path("../gates/support/capture_engine", __dir__)
require File.expand_path("../gates/support/engine_compare", __dir__)

# The engine interface and the cross-engine comparison, on a fake engine. No
# real WebKit or Firefox is driven here: whether safaridriver or geckodriver
# answers on a given Mac is reported by the live run, not proved by this file.
class TestCaptureEngine < Minitest::Test
  CE = Deploy::CaptureEngine
  EC = Deploy::EngineCompare

  # Answers the six verbs from a script; geometry and styles come from Base.
  class FakeEngine < CE::Base
    attr_reader :calls

    def initialize(name, rows:, fail_open: nil)
      @name = name
      @rows = rows
      @fail_open = fail_open
      @calls = []
    end

    def open = (@fail_open ? raise(CE::Unavailable, @fail_open) : self)
    def close = @calls << :close
    def viewport(w, h, mobile: false) = @calls << [:viewport, w, h]
    def navigate(url) = @calls << [:navigate, url]
    def screenshot(path) = File.binwrite(path, "png").then { path }

    def evaluate(js)
      return { "width" => 390, "scroll_width" => 390, "scroll_height" => 800, "rows" => @rows } if js == CE::GEOMETRY_JS

      { "color" => "rgb(0, 0, 0)" }
    end
  end

  Surf = Deploy::GeometryProbe::Surface

  def surface(host: nil) = Surf.new(app: "brgen", label: "home", host:, path: "/", viewport: "mobile", width: 390, height: 844, snapshot: false, port: 1, profile: nil)

  def row(key, x, y, w, h) = { "key" => key, "x" => x, "y" => y, "w" => w, "h" => h }

  def setup = CE.reset!
  def teardown = CE.reset!

  def test_requested_defaults_to_chrome_and_keeps_it_first
    assert_equal ["chrome"], CE.requested({})
    assert_equal %w[chrome webkit firefox], CE.requested({ "MASTER_VISUAL_ENGINES" => "webkit, Firefox, netscape" })
    assert_equal %w[webkit], CE.others({ "MASTER_VISUAL_ENGINES" => "webkit" })
  end

  def test_an_engine_that_cannot_open_is_recorded_and_not_retried
    calls = 0
    factory = ->(name, host_map:) { calls += 1; FakeEngine.new(name, rows: [], fail_open: "not installed") }
    assert_nil CE.open("firefox", factory:)
    assert_nil CE.open("firefox", factory:)
    assert_equal 1, calls
    assert_equal "not installed", CE.unavailable["firefox"]
  end

  def test_base_builds_geometry_and_styles_on_evaluate
    engine = FakeEngine.new("webkit", rows: [row("a", 1, 2, 3, 4)])
    assert_equal 1, engine.geometry["rows"].size
    assert_equal({ "color" => "rgb(0, 0, 0)" }, engine.styles("p", ["color"]))
  end

  def test_diff_reports_boxes_beyond_the_tolerance_largest_first
    ours = { "rows" => [row("a", 0, 0, 100, 20), row("b", 0, 30, 100, 20), row("c", 0, 60, 100, 20), row("only-chrome", 0, 0, 5, 5)] }
    theirs = { "rows" => [row("a", 0, 0, 100, 20), row("b", 0, 34, 100, 20), row("c", 40, 60, 100, 20), row("only-webkit", 0, 0, 5, 5)] }
    found = EC.diff(ours, theirs, tolerance: 8)
    assert_equal %w[c], found["divergences"].map { |d| d["key"] }
    assert_equal 40, found["divergences"].first["delta"]["x"]
    assert_equal [3, 1, 1], [found["compared"], found["only_in_reference"], found["only_in_engine"]]
  end

  class RefCdp
    def viewport(*, **) = nil
    def navigate(url) = url

    def evaluate(_js)
      { "width" => 390, "scroll_width" => 390, "scroll_height" => 800, "rows" => [{ "key" => "a", "x" => 0, "y" => 0, "w" => 100, "h" => 20 }] }
    end
  end

  def test_captures_carry_engine_state_divergences_and_a_screenshot
    engine = FakeEngine.new("webkit", rows: [row("a", 30, 0, 100, 20)])
    Dir.mktmpdir do |dir|
      found = EC.captures(RefCdp.new, surface, dir:, names: ["webkit"], factory: ->(_n, host_map:) { engine })
      assert_equal 1, found.size
      cap = found.first
      assert_equal "engine", cap[:payload].dig("composition", "state")
      assert_equal "home__engine_webkit", cap[:surface].label
      assert_equal 1, cap[:payload].dig("engine", "diverging")
      assert File.file?(cap[:screenshot])
      assert_includes engine.calls, :close
    end
  end

  def test_mapped_host_surfaces_are_not_compared_and_unavailable_engines_yield_nothing
    Dir.mktmpdir do |dir|
      assert_empty EC.captures(RefCdp.new, surface(host: "markedsplass.brgen.no"), dir:, names: ["webkit"])
      gone = ->(n, host_map:) { FakeEngine.new(n, rows: [], fail_open: "no driver") }
      assert_empty EC.captures(RefCdp.new, surface, dir:, names: ["firefox"], factory: gone)
    end
    assert_equal "no driver", CE.unavailable["firefox"]
  end

  def test_firefox_is_unavailable_without_geckodriver_or_firefox
    engine = CE::WebDriverEngine.firefox
    skip "geckodriver and firefox are installed here" if engine.instance_variable_get(:@missing).nil?
    error = assert_raises(CE::Unavailable) { engine.open }
    assert_match(/not found/, error.message)
  end
end
