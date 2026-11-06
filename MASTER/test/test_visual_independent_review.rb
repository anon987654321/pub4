# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "fix/visual_reviewer"
require "fix/visual_simplify"
require "fix/visual_groups"
require File.expand_path("../checks/support/check_result", __dir__)

# The independent reviewer's contract, the guard a cleared group leaves, and the simplify stage
# keeping, reviewing or putting back a reduced stylesheet.
class TestVisualIndependentReview < Minitest::Test
  Review = Master::Fix::VisualReviewer
  Guards = Deploy::RegressionGuards
  BOX = { x: 0, y: 0, w: 8, h: 8 }.freeze

  def png(path, grey)
    File.binwrite(path, Deploy::PngDiff.encode_rgba(16, 16, ([grey, grey, grey, 255] * 256).pack("C*")))
    path
  end

  def group(dir)
    Master::Fix::VisualGroups::Group.new(key: "k", id: "g1", law: "RenderedGeometryCheck/geometry spacing",
                                         members: ["geometry spacing: brgen/core/mobile div.card padding-top 10px"],
                                         surfaces: ["brgen/core/mobile"], before: [],
                                         after: [png(File.join(dir, "a.png"), 0)])
  end

  def test_the_brief_names_the_laws_the_principles_and_every_region_and_the_crops_are_4x
    Dir.mktmpdir do |dir|
      seen = []
      Review.judge(group(dir), [BOX], reviewer: ->(brief, crops) { (seen << brief << crops) && "REJECT: no" })
      brief, crops = seen

      assert_match(/Laws: RenderedGeometryCheck\/geometry spacing/, brief)
      assert_match(/Swiss\/International typographic style.*Bringhurst.*Mueller-Brockmann/m, brief)
      assert_match(/R1 0,0 8x8/, brief)
      assert_equal [64, 64], Deploy::PixelMatch.read(crops.first).size
    end
  end

  def answered(found, answer) = Review.judge(found, [BOX, BOX], reviewer: ->(_brief, _crops) { answer })

  def test_only_an_approval_that_explains_every_region_approves
    Dir.mktmpdir do |dir|
      answers = ["APPROVE\nR1: EIGHT_PX_RHYTHM, 10px became 8px\nR2: same rule", "APPROVE\nR1: fine",
                 "REJECT: R2 moved"]
      verdicts = answers.map { |answer| answered(group(dir), answer) }

      assert_equal [:approved, "rejected: R2 left unexplained", "rejected: R2 moved"], verdicts
      assert_equal "no independent reviewer configured", Review.judge(group(dir), [BOX], reviewer: nil)
    end
  end

  def test_a_guarded_finding_reports_hard_where_an_unguarded_one_stays_soft
    Dir.mktmpdir do |dir|
      path = File.join(dir, "surfaces.yml")
      File.write(path, "regression_guards:\n")
      Guards.record(kind: "geometry spacing", place: { selector: "div.card" }, surfaces: ["brgen/core/mobile"], path:)
      Guards.record(kind: "geometry spacing", place: { selector: "div.card" }, surfaces: ["brgen/core/mobile"], path:)
      rows = Guards.rows(path)

      assert_equal 1, rows.size
      result = Deploy::CheckResult.new
      Guards.stub(:cached, rows) do
        %w[brgen/core/mobile amber/home/mobile].each do |surface|
          result.fail("geometry spacing: #{surface} 1 computed value(s) - div.card padding-top 10px", severity: :soft)
        end
      end

      assert_equal 1, result.failures.size
      assert result.failures.first.start_with?("[guarded] geometry spacing: brgen/core/mobile")
    end
  end

  def stage(dir, pixels:, review: nil, committed: [])
    after = png(File.join(dir, "after.png"), pixels ? 0 : 255)
    shots = lambda do |_path, &edit|
      edit.call
      [[png(File.join(dir, "before.png"), 255), after]]
    end
    Master::Fix::VisualSimplify::Stage.new(repo_root: dir, shots:, review:, commit: ->(path) { committed << path })
  end

  def sheet(dir)
    path = File.join(dir, "_card.scss")
    File.write(path, ".card { padding: 8px; }\n.card-copy { padding: 8px; }\n")
    path
  end

  def test_a_reduction_with_no_changed_pixel_is_kept_and_committed
    Dir.mktmpdir do |dir|
      committed = []
      path = sheet(dir)

      assert_equal [:applied], stage(dir, pixels: false, committed:).run([path])
      assert_equal [path], committed
      assert_equal ".card, .card-copy { padding: 8px; }\n", File.read(path)
    end
  end

  def test_a_visible_reduction_goes_to_the_reviewer_and_is_put_back_when_not_approved
    Dir.mktmpdir do |dir|
      asked = []
      path = sheet(dir)
      review = ->(found, regions) { (asked << [found.law, regions.size]) && "rejected: R1 moved" }

      assert_equal [:visible_change_not_approved], stage(dir, pixels: true, review:).run([path])
      assert_equal [["AESTHETIC_MINIMALISM", 1]], asked
      assert_includes File.read(path), ".card-copy { padding: 8px; }"
    end
  end
end
