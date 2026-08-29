# frozen_string_literal: true

require "test_helper"

# TODO.md, Test coverage: no test named PatchApplier. It shells out to patch(1) and
# is the mechanism every diff-mode autofix goes through, so "rejects malformed or
# no-op patches; never applies blindly" needs to be more than a comment.
class PatchApplierTest < Minitest::Test
  Applier = Master::Fix::PatchApplier

  ORIGINAL = "line one\nline two\nline three\n"

  def diff(from: "line two", to: "line TWO")
    <<~DIFF
      --- a
      +++ b
      @@ -1,3 +1,3 @@
       line one
      -#{from}
      +#{to}
       line three
    DIFF
  end

  def test_applies_a_valid_unified_diff
    result = Applier.apply(ORIGINAL, diff)

    assert_instance_of Applier::Success, result
    assert_equal "line one\nline TWO\nline three\n", result.source
  end

  def test_rejects_an_empty_diff_without_shelling_out
    ["", "   \n\n"].each do |empty|
      result = Applier.apply(ORIGINAL, empty)

      assert_instance_of Applier::Failure, result
      assert_equal "empty diff", result.reason
    end
  end

  # A hunk whose context does not exist must not be applied partially — and the
  # reason has to say something. patch(1) reports a failed hunk on stdout, so
  # keeping only stderr produced Failure(reason: "") for exactly this case.
  def test_rejects_a_diff_that_does_not_match_the_source_and_says_why
    result = Applier.apply(ORIGINAL, diff(from: "line seventeen", to: "line SEVENTEEN"))

    assert_instance_of Applier::Failure, result
    refute_empty result.reason
    assert_match(/hunk|fail|reject/i, result.reason)
  end

  def test_rejects_garbage_that_is_not_a_diff
    result = Applier.apply(ORIGINAL, "this is not a patch at all\n")

    assert_instance_of Applier::Failure, result
  end

  # "never applies blindly" — a patch that changes nothing is an error, not a
  # success with identical output, or an autofix loop would report progress forever.
  def test_rejects_a_no_op_patch
    identity = <<~DIFF
      --- a
      +++ b
      @@ -1,3 +1,3 @@
       line one
      -line two
      +line two
       line three
    DIFF

    result = Applier.apply(ORIGINAL, identity)

    assert_instance_of Applier::Failure, result
    assert_equal "no change", result.reason
  end

  def test_failure_reasons_are_truncated
    result = Applier.apply(ORIGINAL, "@@ bogus @@\n#{"x" * 5_000}\n")

    assert_instance_of Applier::Failure, result
    assert_operator result.reason.length, :<=, 200
  end

  def test_the_diff_threshold_is_declared
    assert_equal 8_192, Applier::DIFF_THRESHOLD
  end
end
