# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require File.expand_path("../lib/fix/best_of_n", __dir__)

# Candidates are CSS strings; the fake renderer reads the file the pass just
# wrote and answers with a payload whose quality depends on it. That proves the
# selection (regressions dropped, best score wins, smallest diff breaks ties)
# and that the original is back on disk after every candidate.
class BestOfNTest < Minitest::Test
  Surface = Struct.new(:id, :viewport)
  B = Master::Fix::BestOfN
  S = Master::Fix::LayoutScoreStore

  def setup
    @root = Dir.mktmpdir("bon")
    FileUtils.mkdir_p(File.join(@root, "RAILS/__shared"))
    File.write(File.join(@root, "RAILS/__shared/design_tokens.yml"),
               YAML.dump("scale" => { "space_px" => [0, 4, 8, 16, 24, 32] }))
    @surface = Surface.new("brgen/home/mobile", "mobile")
    @path = File.join(@root, "card.scss")
    @original = ".a { margin: 13px; }\n"
    File.write(@path, @original)
    S.seed(@surface, rendering("mid"), root: @root)
  end

  def teardown = FileUtils.remove_entry(@root)

  def el(x, y, **over) = { "key" => "k#{x}#{y}", "visible" => true, "onscreen" => true, "tag" => "p", "text" => "t", "rect" => { "x" => x, "y" => y, "w" => 300, "h" => 30 } }.merge(over)

  # mid: a few edges, gaps half on scale; good: aligned and on scale; bad: ragged
  def rendering(kind)
    gaps, xs = { "good" => [[16, 16, 16], [16] * 6], "mid" => [[16, 13, 16], [16, 16, 16, 40, 16, 16]], "bad" => [[13, 19, 7], (0..11).map { |i| 3 + i * 17 }] }.fetch(kind)
    { "vw" => 400, "vh" => 800, "gaps" => gaps.map { |g| { "gap" => g } }, "elements" => xs.each_with_index.map { |x, i| el(x, i * 46, "line_height" => 24) } }
  end

  def measurer = ->(_surfaces, root:) { [[@surface, rendering(File.read(@path)[/kind-(\w+)/, 1] || "mid")]] }
  def write = ->(src) { File.write(@path, src) }

  def rank(*candidates, **over)
    B.rank(candidates, original: @original, surfaces: [@surface], root: @root, measurer:, write:, **over)
  end

  def test_the_best_scoring_candidate_wins_and_the_original_is_restored
    good = ".a { margin: 16px; } /* kind-good */\n"
    mid = ".a { margin: 12px; } /* kind-mid */\n"
    assert_equal good, rank(mid, good)
    assert_equal @original, File.read(@path)
  end

  def test_regressing_candidates_are_discarded
    bad = ".a { margin: 3px; } /* kind-bad */\n"
    assert_nil rank(bad)
    assert_equal @original, File.read(@path)
  end

  def test_ties_go_to_the_smallest_diff
    small = ".a { margin: 16px; } /* kind-good */\n"
    big = ".a { margin: 16px; }\n.b { margin: 16px; }\n.c { margin: 16px; } /* kind-good */\n"
    assert_equal small, rank(big, small)
  end

  def test_empty_unchanged_and_duplicate_candidates_are_ignored
    assert_nil rank("", @original, "  ")
  end

  def test_unrenderable_candidates_are_discarded
    none = ->(_s, root:) { [] }
    assert_nil B.rank([".a{}"], original: @original, surfaces: [@surface], root: @root, measurer: none, write:)
  end

  def test_one_candidate_keeps_todays_behaviour
    ENV.delete("MASTER_FIX_BEST_OF")
    assert_equal 1, B.n
    refute B.active?({ law: B::LAW_ID, file: "x.scss" }, Object.new)
  end

  def test_active_only_for_visual_style_findings_with_n_above_one
    ENV["MASTER_FIX_BEST_OF"] = "3"
    assert_equal 3, B.n
    assert B.active?({ law: B::LAW_ID, file: "x.scss" }, Object.new)
    refute B.active?({ law: "OTHER", file: "x.scss" }, Object.new)
    refute B.active?({ law: B::LAW_ID, file: "x.erb" }, Object.new)
    refute B.active?({ law: B::LAW_ID, file: "x.scss" }, nil)
  ensure
    ENV.delete("MASTER_FIX_BEST_OF")
  end

  class FakeLoop
    def initialize(replies) = (@replies = replies; @visual_image = nil)
    def build_prompt_for(violation:, src:, path:) = "fix #{path}"
    def ask_agent(prompt, image: nil) = @replies.shift
    def extract_code(text, _ext) = text
    def write_atomic(path, src) = File.write(path, src)
  end

  def test_pick_asks_for_n_minus_one_more_and_returns_the_winner
    ENV["MASTER_FIX_BEST_OF"] = "3"
    custody = Struct.new(:surfaces).new([@surface])
    good = ".a { margin: 16px; } /* kind-good */\n"
    loop = FakeLoop.new([".a { margin: 3px; } /* kind-bad */\n", good])
    violation = { law: B::LAW_ID, file: @path }
    first = ".a { margin: 12px; } /* kind-mid */\n"
    assert_equal good, B.pick(loop, violation, first, custody:, root: @root, measurer:)
    assert_equal @original, File.read(@path)
  ensure
    ENV.delete("MASTER_FIX_BEST_OF")
  end
end
