# frozen_string_literal: true

require_relative "test_helper"

# A /fix run that committed verified fixes and then stopped short is partial success, not failure.
class TestFixPartialOutcome < Minitest::Test
  Pass = Master::CLI::Pipeline::Pass

  def outcome(ok:, msg:, delivered: 0) = Pass.fix_outcome(ok:, msg:, delivered:)

  def test_a_clean_run_is_done
    assert_equal :done, outcome(ok: true, msg: "DONE: clean after 2 passes")
  end

  def test_a_plateau_after_commits_is_partial
    assert_equal :partial, outcome(ok: false, msg: "PLATEAU: no further improvement", delivered: 3)
    assert_equal :partial, outcome(ok: true, msg: "TIMEOUT: run budget spent", delivered: 1)
  end

  def test_a_plateau_with_no_commits_still_fails
    assert_equal :failed, outcome(ok: false, msg: "PLATEAU: no further improvement")
  end

  def test_a_crash_is_never_partial
    assert_equal :failed, outcome(ok: false, msg: "CRASH: NoMethodError", delivered: 5)
    assert_equal :incomplete, outcome(ok: true, msg: "DELIVERY_FAILED: conflict", delivered: 2)
  end
end
