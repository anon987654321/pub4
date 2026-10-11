# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require File.expand_path("../lib/fix/layout_score_store", __dir__)
require File.expand_path("../lib/fix/visual_quality_gates", __dir__)

# Synthetic payloads in the GeometryProbe shape. Each sub-score gets a clean
# and a broken layout; the store cases prove a drop past tolerance is a
# regression and an improvement moves the baseline up.
class LayoutScoreTest < Minitest::Test
  Surface = Struct.new(:id, :viewport)
  L = Master::Fix::LayoutScore
  S = Master::Fix::LayoutScoreStore

  def setup
    @root = Dir.mktmpdir("ls")
    FileUtils.mkdir_p(File.join(@root, "RAILS/__shared"))
    File.write(File.join(@root, "RAILS/__shared/design_tokens.yml"),
               YAML.dump("scale" => { "space_px" => [0, 4, 8, 16, 24, 32], "radius_px" => [0, 4, 8] },
                         "shared_chrome" => { "font_size_body" => "1rem", "font_size_title" => "1.25rem" }))
    @tokens = Master::Fix::LayoutScoreTokens.load(@root)
    @surface = Surface.new("brgen/home/mobile", "mobile")
  end

  def teardown = FileUtils.remove_entry(@root)

  def el(x, y, w, h, **over)
    { "key" => "k#{x}#{y}", "visible" => true, "onscreen" => true, "tag" => "p", "text" => "t",
      "rect" => { "x" => x, "y" => y, "w" => w, "h" => h } }.merge(over)
  end

  def payload(els, **over) = { "vw" => 400, "vh" => 800, "elements" => els }.merge(over)

  def compute(els, **over) = L.compute(payload(els, **over), tokens: @tokens)

  def test_tokens_come_from_files
    assert_equal [0.0, 4.0, 8.0, 16.0, 24.0, 32.0], @tokens.space_px
    assert_equal 8, @tokens.base_unit
    assert_in_delta 1.25, @tokens.type_ratio
  end

  def test_edges_cluster_at_two_pixels
    aligned = (0..9).map { |i| el(16 + (i.odd? ? 1 : 0), i * 40, 300, 30) }
    ragged = (0..9).map { |i| el(10 + i * 9, i * 40, 100, 30) }
    assert_equal 1, compute(aligned).facts["edges"]
    assert_equal 10, compute(ragged).facts["edges"]
    assert_equal 1.0, compute(aligned).subs["edges"]
    assert_operator compute(ragged).subs["edges"], :<, 0.7
  end

  def test_grid_rewards_rhythm_and_penalises_drift
    on = payload([el(16, 0, 300, 24, "line_height" => 24)], "gaps" => [{ "gap" => 16 }, { "gap" => 24 }])
    off = payload([el(16, 0, 300, 24, "line_height" => 22)], "gaps" => [{ "gap" => 14 }, { "gap" => 18 }])
    assert_equal 1.0, L.compute(on, tokens: @tokens).subs["grid"]
    assert_equal 0.0, L.compute(off, tokens: @tokens).subs["grid"]
  end

  def test_scale_ratio_counts_spacing_values_on_the_scale
    ratio = ->(gaps) { L.compute(payload([el(16, 0, 300, 24)], "gaps" => gaps.map { |g| { "gap" => g } }), tokens: @tokens).subs["scale"] }
    assert_equal 1.0, ratio.([8, 16, 24, 32])
    assert_in_delta 0.5, ratio.([8, 16, 17.5, 21])
    assert_nil L.compute(payload([el(16, 0, 300, 24)]), tokens: @tokens).subs["scale"]
  end

  def test_measure_penalises_long_and_short_lines
    para = ->(w) { el(16, 0, w, 100, "text_lines" => 4, "font_size" => 16) }
    assert_equal 1.0, compute([para.(480)]).subs["measure"]
    assert_equal 0, compute([para.(480)]).facts["outliers"]
    long = compute([para.(1000)])
    assert_equal 0.0, long.subs["measure"]
    assert_equal 1, long.facts["outliers"]
    assert_operator compute([para.(300)]).subs["measure"], :<, 1.0
  end

  def test_heading_ratio_follows_the_modular_scale
    vis = { "typography" => { "body_median_px" => 16 } }
    head = ->(px) { el(16, 0, 300, 40, "tag" => "h1", "font_size" => px) }
    assert_equal 1.0, compute([head.(20)], "visual" => vis).subs["heading"]
    assert_in_delta 1.0, compute([head.(25)], "visual" => vis).subs["heading"], 0.01
    assert_operator compute([head.(22.5)], "visual" => vis).subs["heading"], :<, 0.2
    assert_equal 0.0, compute([head.(12)], "visual" => vis).subs["heading"]
  end

  def test_density_and_centering
    full = compute([el(0, 0, 400, 400)])
    assert_equal 1.0, full.subs["density"]
    assert_equal 1.0, full.subs["centering"]
    sparse = compute([el(0, 0, 40, 40)])
    assert_operator sparse.subs["density"], :<, 0.1
    assert_operator sparse.subs["centering"], :<, 0.5
  end

  def test_missing_parts_redistribute_weight
    result = compute([])
    assert_equal 0.0, result.score
    only_edges = compute([el(16, 0, 300, 24)])
    assert_operator only_edges.score, :>, 0.0
    assert_operator only_edges.score, :<=, 100.0
  end

  def good_payload = payload([el(16, 0, 368, 200, "text_lines" => 3, "font_size" => 16, "line_height" => 24)], "gaps" => [{ "gap" => 16 }, { "gap" => 16 }, { "gap" => 16 }])
  def bad_payload = payload((0..11).map { |i| el(5 + i * 13, i * 30, 90, 20, "line_height" => 19) }, "gaps" => [{ "gap" => 13 }, { "gap" => 19 }, { "gap" => 7 }])

  def test_store_rejects_a_drop_and_accepts_improvement
    S.seed(@surface, bad_payload, root: @root)
    assert_empty S.judge(@surface, good_payload, root: @root)
    S.settle([[@surface, good_payload]], root: @root)
    refused = S.judge(@surface, bad_payload, root: @root)
    assert_equal 1, refused.size
    assert_match(/layout score/, refused.first)
    history = S.load(@root, @surface)
    assert_equal 2, history["history"].size
    assert_operator history.dig("baseline", "score"), :>, 50
  end

  def test_store_without_baseline_never_blocks
    assert_empty S.judge(@surface, bad_payload, root: @root)
  end

  def test_evidence_row_names_the_score
    capture = { surface: @surface, payload: good_payload.merge("composition" => { "state" => "resting" }) }
    row = S.row(capture, root: @root)
    assert_match(%r{layout score brgen/home/mobile \d+\.\d edges 1}, row)
    assert_match(/weakest:/, row)
    assert_nil S.row(capture.merge(payload: good_payload.merge("composition" => { "state" => "open" })), root: @root)
  end

  def test_quality_gates_judge_rejects_a_layout_score_regression
    Master::Fix::VisualQualityGates.record([{ surface: @surface, payload: good_payload.merge("composition" => { "state" => "resting" }) }], root: @root)
    verdict = Master::Fix::VisualQualityGates.judge([[@surface, bad_payload]], root: @root, prior: Master::Result.ok(state: :preserved))
    assert verdict.err?
    assert_match(/layout score/, verdict.message)
  end
end
