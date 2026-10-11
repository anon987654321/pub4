# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require File.expand_path("../lib/fix/visual_quality_gates", __dir__)

# Synthetic payloads in the shape GeometryProbe.walk returns. Each metric gets
# one case that fails and one that passes; the judge cases prove a worsened
# metric rejects, an equal one passes, and chrome drift needs approval.
class VisualQualityGatesTest < Minitest::Test
  Surface = Struct.new(:id, :viewport)
  Q = Master::Fix::VisualQualityGates
  D = Master::Fix::VisualDriftBudget

  def setup
    @root = Dir.mktmpdir("vq")
    @surface = Surface.new("brgen/home/mobile", "mobile")
  end

  def teardown = FileUtils.remove_entry(@root)

  def el(key, **over)
    { "key" => key, "visible" => true, "text" => "", "rect" => { "x" => 0, "y" => 0, "w" => 100, "h" => 50 } }.merge(over)
  end

  def payload(*elements, **over)
    { "vw" => 390, "vh" => 800, "scroll_width" => 390, "client_width" => 390, "elements" => elements }.merge(over)
  end

  def metrics(*elements, **over) = Q.measure(@surface, payload(*elements, **over))["metrics"]

  def test_contrast_uses_aa_thresholds_and_large_text
    assert_equal 1, metrics(el("a", "text" => "x", "color" => "#777777", "bg" => "#888888", "font_size" => 16))["contrast"]
    assert_equal 0, metrics(el("a", "text" => "x", "color" => "#000000", "bg" => "#ffffff", "font_size" => 16))["contrast"]
    assert_equal 0, metrics(el("a", "text" => "x", "color" => "#767676", "bg" => "#ffffff", "font_size" => 28))["contrast"]
  end

  def test_tap_target_only_on_mobile_and_not_inline
    small = el("b", "interactive" => true, "rect" => { "x" => 0, "y" => 0, "w" => 30, "h" => 30 })
    assert_equal 1, metrics(small)["tap_target"]
    assert_equal 0, metrics(small, "vw" => 1280)["tap_target"]
    assert_equal 0, metrics(small.merge("inline_in_text" => true))["tap_target"]
  end

  def test_focus_order_counts_upward_jumps
    low = el("a", "interactive" => true, "rect" => { "x" => 0, "y" => 400, "w" => 60, "h" => 60 })
    high = el("b", "interactive" => true, "rect" => { "x" => 0, "y" => 20, "w" => 60, "h" => 60 })
    assert_equal 1, metrics(low, high)["focus_order"]
    assert_equal 0, metrics(high, low)["focus_order"]
  end

  def test_overflow_and_i18n
    assert_equal 1, metrics(el("a"), "scroll_width" => 500)["overflow"]
    assert_equal 1, metrics(el("a", "text" => "translation missing: nb.home.title"))["i18n"]
    assert_equal 1, metrics(el("a", "text" => "home.index.title"))["i18n"]
    assert_equal 0, metrics(el("a", "text" => "www.brgen.no"), el("b", "text" => "Hjem"))["i18n"]
  end

  def test_layout_shift_is_zero_without_baseline_and_positive_when_moved
    box = el("a", "rect" => { "x" => 0, "y" => 0, "w" => 390, "h" => 400 })
    assert_equal 0.0, metrics(box)["layout_shift"]
    moved = box.merge("rect" => { "x" => 0, "y" => 200, "w" => 390, "h" => 400 })
    shifted = Q.measure(@surface, payload(moved), baseline_rects: { "a" => [0, 0, 390, 400] })
    assert_operator shifted["metrics"]["layout_shift"], :>, 0.1
  end

  def captures(payload) = [{ surface: @surface, payload: payload.merge("composition" => { "state" => "resting" }) }]
  def ok = Master::Result.ok(state: :preserved)

  def test_judge_rejects_a_worse_metric_and_names_it
    Q.record(captures(payload(el("a"))), root: @root)
    worse = payload(el("a", "interactive" => true, "rect" => { "x" => 0, "y" => 0, "w" => 20, "h" => 20 }))
    verdict = Q.judge([[@surface, worse]], root: @root, prior: ok)
    refute verdict.ok?
    assert_match(/tap_target 0->1/, verdict.message)
  end

  def test_judge_accepts_equal_and_advances_baseline
    Q.record(captures(payload(el("a", "text" => "x", "color" => "#777777", "bg" => "#888888"))), root: @root)
    better = payload(el("a", "text" => "x", "color" => "#000000", "bg" => "#ffffff"))
    assert Q.judge([[@surface, better]], root: @root, prior: ok).ok?
    assert_equal 0, Q.load(@root, @surface)["metrics"]["contrast"]
  end

  def test_judge_keeps_a_failing_prior
    prior = Master::Result.err("custody", category: :policy)
    assert_equal prior, Q.judge([[@surface, payload(el("a"))]], root: @root, prior:)
  end

  def header(y) = el("body>header.site>nav.top", "rect" => { "x" => 0, "y" => y, "w" => 390, "h" => 56 })

  def test_chrome_drift_fails_until_approved
    Q.record(captures(payload(header(0))), root: @root)
    moved = payload(header(12))
    verdict = Q.judge([[@surface, moved]], root: @root, prior: ok)
    refute verdict.ok?
    assert_match(/chrome drift.*y\+12/, verdict.message)
    assert_equal [@surface.id.tr("/", "_")], D.pending(@root)
    assert_equal 1, D.approve(@surface.id, root: @root)
    assert Q.judge([[@surface, moved]], root: @root, prior: ok).ok?
  end

  def test_anchored_chrome_move_is_exempt_and_never_auto_blessed
    Q.record(captures(payload(header(0))), root: @root)
    assert_empty D.check(@surface, payload(header(12)), root: @root, anchors: ["nav.top"])
    assert_nil D.approve(@surface.id, root: @root)
    Q.record(captures(payload(header(30))), root: @root)
    refute_empty D.check(@surface, payload(header(12)), root: @root)
  end
end
