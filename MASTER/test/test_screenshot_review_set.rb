# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../lib/fix/screenshot_sweep"

# The review set at RAILS/screenshot_*.png is replaced whole by each sweep, and
# old sweep folders are pruned, so neither keeps growing.
class TestScreenshotReviewSet < Minitest::Test
  Row = Data.define(:app, :shots)
  ReviewSet = Master::Fix::ScreenshotSweep::ReviewSet
  SWEEPS = %w[sweep-20261101T000000Z sweep-20261102T000000Z sweep-20261103T000000Z sweep-20261104T000000Z].freeze

  def png(path)
    FileUtils.mkdir_p(File.dirname(path))
    File.binwrite(path, "PNG")
  end

  def test_a_sweep_replaces_the_whole_review_set_with_its_phone_width_shots
    Dir.mktmpdir do |root|
      rails = File.join(root, "RAILS")
      sweep = File.join(root, "MASTER", ".master", "visual_artifacts", SWEEPS.last)
      png(File.join(rails, "screenshot_amber_gone.png"))
      png(File.join(rails, "keep_me.png"))
      %w[w390 w1280].each { |width| png(File.join(sweep, "brgen", "brgen_no", "#{width}.png")) }
      shots = { "390" => "brgen/brgen_no/w390.png", "1280" => "brgen/brgen_no/w1280.png" }

      assert_equal 1, ReviewSet.new(root:, sweep_dir: sweep).publish!([Row.new(app: "brgen", shots:)])
      assert_equal %w[keep_me.png screenshot_brgen_brgen_no.png], Dir.children(rails).sort
    end
  end

  def test_a_sweep_that_captured_nothing_keeps_the_last_set
    Dir.mktmpdir do |root|
      png(File.join(root, "RAILS", "screenshot_brgen_brgen_no.png"))

      assert_equal 0, ReviewSet.new(root:, sweep_dir: File.join(root, "sweep-x")).publish!([])
      assert File.exist?(File.join(root, "RAILS", "screenshot_brgen_brgen_no.png"))
    end
  end

  def test_only_the_newest_sweeps_are_kept_and_nothing_else_is_touched
    Dir.mktmpdir do |root|
      base = File.join(root, "visual_artifacts")
      (SWEEPS + %w[notes]).each { |name| FileUtils.mkdir_p(File.join(base, name)) }

      pruned = ReviewSet.new(root:, sweep_dir: File.join(base, SWEEPS.last)).prune!

      assert_equal 2, pruned
      assert_equal %w[notes] + SWEEPS.last(2), Dir.children(base).sort
    end
  end
end
