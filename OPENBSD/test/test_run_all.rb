# frozen_string_literal: true

require "minitest/autorun"
require_relative "run_all"

class TestOpenBSDRunAll < Minitest::Test
  CommandStatus = Struct.new(:ok, :exitstatus) do
    def success? = ok
  end

  def test_parses_a_minitest_summary
    assert_equal(
      { runs: 3, assertions: 7, failures: 0, errors: 0, skips: 1 },
      OpenBSDTestRunner.parse_summary("3 runs, 7 assertions, 0 failures, 0 errors, 1 skips\n")
    )
  end

  def test_accepts_only_a_nonempty_clean_run
    result = OpenBSDTestRunner.classify(
      "1 runs, 2 assertions, 0 failures, 0 errors, 0 skips\n",
      CommandStatus.new(true, 0)
    )

    assert_equal :pass, result.first
    assert_nil result[1]
  end

  def test_blocks_a_successful_process_that_runs_zero_tests
    result = OpenBSDTestRunner.classify(
      "0 runs, 0 assertions, 0 failures, 0 errors, 0 skips\n",
      CommandStatus.new(true, 0)
    )

    assert_equal :blocked, result.first
    assert_equal "Minitest reported zero runs", result[1]
  end

  def test_blocks_a_successful_process_without_a_valid_summary
    result = OpenBSDTestRunner.classify("nothing ran\n", CommandStatus.new(true, 0))

    assert_equal :blocked, result.first
    assert_equal "no valid Minitest summary", result[1]
  end

  def test_rejects_failure_counts_even_when_the_process_exits_zero
    result = OpenBSDTestRunner.classify(
      "1 runs, 2 assertions, 1 failures, 0 errors, 0 skips\n",
      CommandStatus.new(true, 0)
    )

    assert_equal :fail, result.first
    assert_equal "Minitest reported 1 failures and 0 errors", result[1]
  end

  def test_rejects_a_nonzero_process_even_with_a_clean_summary
    result = OpenBSDTestRunner.classify(
      "1 runs, 2 assertions, 0 failures, 0 errors, 0 skips\n",
      CommandStatus.new(false, 1)
    )

    assert_equal :fail, result.first
    assert_equal "test process exited 1", result[1]
  end
end
