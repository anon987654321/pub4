# frozen_string_literal: true

require_relative "test_helper"

# VISUAL_LAYOUT_REFINEMENT_EVIDENCE: a layout refinement ships only with its
# measured evidence — a distinct, existing before/after screenshot pair, the
# viewport the pair was captured at, and the Law citations naming what each
# edit repairs.
class TestVisualLayoutRefinement < Minitest::Test
  def fixture_pair(dir)
    before = File.join(dir, "before.png")
    after = File.join(dir, "after.png")
    File.write(before, "png-before")
    File.write(after, "png-after")
    [before, after]
  end

  def test_complete_record_passes
    Dir.mktmpdir do |dir|
      before, after = fixture_pair(dir)
      verdict = Master::Visual::LayoutRefinement.evidence(
        record: {
          laws: "VISUAL_HIERARCHY,VISUAL_IDENTITY_TOKENS_ONLY",
          before:, after:,
          viewport: "1280x900",
        },
      )

      assert_equal true, verdict[:pass], verdict[:reasons]
      assert_equal "VISUAL_LAYOUT_REFINEMENT_EVIDENCE", verdict[:law]
    end
  end

  def test_missing_fields_name_their_gap
    verdict = Master::Visual::LayoutRefinement.evidence(record: {})

    assert_equal false, verdict[:pass]
    %w[laws before after viewport].each do |field|
      assert verdict[:reasons].include?("refinement record is missing #{field}"), verdict[:reasons]
    end
  end

  def test_same_screenshot_is_refused_even_when_the_file_exists
    Dir.mktmpdir do |dir|
      real = File.join(dir, "real.png")
      File.write(real, "png")
      verdict = Master::Visual::LayoutRefinement.evidence(
        record: { laws: "VISUAL_HIERARCHY", before: real, after: real, viewport: "1280x900" },
      )

      reasons = verdict[:reasons]
      assert_equal false, verdict[:pass]
      assert reasons.include?("before and after point at the same screenshot"), reasons
      assert reasons.none?("after screenshot is not present at #{real}"), reasons
    end
  end

  def test_screenshot_paths_that_do_not_exist_are_refused
    Dir.mktmpdir do |dir|
      verdict = Master::Visual::LayoutRefinement.evidence(
        record: {
          laws: "VISUAL_HIERARCHY",
          before: File.join(dir, "gone-before.png"),
          after: File.join(dir, "gone-after.png"),
          viewport: "1280x900",
        },
      )

      reasons = verdict[:reasons]
      assert_equal false, verdict[:pass]
      assert reasons.include?("before screenshot is not present at #{File.join(dir, 'gone-before.png')}"), reasons
      assert reasons.include?("after screenshot is not present at #{File.join(dir, 'gone-after.png')}"), reasons
    end
  end

  def test_bad_viewport_and_uncited_repairs_are_refused
    Dir.mktmpdir do |dir|
      before, after = fixture_pair(dir)
      verdict = Master::Visual::LayoutRefinement.evidence(
        record: { laws: "", before:, after:, viewport: "big" },
      )

      reasons = verdict[:reasons]
      assert_equal false, verdict[:pass]
      assert reasons.include?("refinement record cites no Law for the repairs it claims"), reasons
      assert reasons.include?("viewport must declare width and height, like 1280x900"), reasons
    end
  end

  def test_non_hash_record_is_refused_without_crash
    verdict = Master::Visual::LayoutRefinement.evidence(record: "before.png")

    assert_equal false, verdict[:pass]
    assert verdict[:reasons].include?("refinement record is missing entirely")
  end
end
