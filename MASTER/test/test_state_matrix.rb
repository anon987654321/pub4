# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require File.expand_path("../checks/support/geometry_probe", __dir__)
require File.expand_path("../checks/support/state_matrix", __dir__)

# The state matrix on a fake session: the plan's mobile-first order and cap, the crop each cell
# takes, and the two findings - a focus state no one can see, and an overflowing component.
class TestStateMatrix < Minitest::Test
  SM = Deploy::StateMatrix
  CONFIG = Deploy::GeometryProbe.config["state_matrix"]

  # Paints each cell's crop a colour chosen by the state the session was last put in.
  class FakeCdp
    attr_reader :calls

    def initialize(focus_paints:, overflow_at: nil)
      @focus_paints = focus_paints
      @overflow_at = overflow_at
      @calls = []
      @state = "default"
    end

    def viewport(width, _height, mobile:, scale:) = (@width = width) && @calls << [:viewport, width, mobile, scale]
    def command(method, **params) = @calls << [method, params]
    def headers(hash) = @calls << [:headers, hash]
    def navigate(_url) = @state = "default"

    def force_pseudo_state(_selector, states)
      @state = states.include?("focus-visible") ? "focus" : "default"
      true
    end

    def evaluate(script)
      return unless script.include?("getBoundingClientRect")

      { "x" => 16, "y" => 100, "w" => 120, "h" => 44, "overflow" => @width == @overflow_at }
    end

    def screenshot(path, clip:)
      @calls << [:clip, clip]
      grey = @state == "focus" && @focus_paints ? 0 : 255
      File.binwrite(path, Deploy::PngDiff.encode_rgba(4, 4, ([grey, grey, grey, 255] * 16).pack("C*")))
      path
    end
  end

  def capture(cdp, dir)
    SM.capture(cdp, SM::Target.new(url: "http://127.0.0.1:1/", selector: "main button"), cells: SM.plan(CONFIG), dir:)
  end

  def test_the_plan_is_every_state_at_390_then_narrower_widths_and_stops_at_the_cap
    cells = SM.plan(CONFIG)

    assert_equal 12, cells.size
    states = %w[default hover focus-visible active disabled loading error empty long-text]

    assert_equal states, cells.first(9).map(&:state)
    assert(cells.first(9).all? { |cell| cell.width == 390 })
    assert_equal [360, 320, 768], cells.drop(9).map(&:width)
  end

  def test_every_variant_is_planned_when_the_cap_allows
    cells = SM.plan(CONFIG.merge("cells_per_component" => 99))

    assert_includes cells.map(&:label), "default 640px x2 nb light"
    assert_includes cells.map(&:label), "default 390px en light"
    assert_includes cells.map(&:label), "default 390px nb dark"
  end

  def test_a_focus_state_identical_to_default_is_a_finding
    Dir.mktmpdir do |dir|
      rows = capture(FakeCdp.new(focus_paints: false), dir)

      assert_equal ["state_matrix unseen_state: c focus-visible 390px nb light renders identically to default " \
                    "law=FOCUS_VISIBLE"], SM.judge("c", rows, must_differ: ["focus-visible"])
    end
  end

  def test_a_visible_focus_state_is_quiet_and_overflow_is_named
    Dir.mktmpdir do |dir|
      rows = capture(FakeCdp.new(focus_paints: true, overflow_at: 320), dir)

      expected = "state_matrix overflow: c default 320px nb light overflows its box or the viewport " \
                 "law=INTRINSIC_LAYOUT"

      assert_equal [expected], SM.judge("c", rows, must_differ: ["focus-visible"])
    end
  end

  def test_each_cell_is_cropped_to_its_component_and_tiled_into_one_image
    Dir.mktmpdir do |dir|
      cdp = FakeCdp.new(focus_paints: true)
      rows = capture(cdp, dir)
      sheet = Deploy::PixelMatch.read(SM.composite(rows, out: File.join(dir, "sheet.png")))

      assert_includes cdp.calls, [:clip, { x: 8.0, y: 92.0, width: 136.0, height: 60.0 }]
      assert_equal [16, 12], sheet.size
    end
  end
end
