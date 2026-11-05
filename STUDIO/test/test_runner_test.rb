# frozen_string_literal: true

require_relative "minitest_helper"
require_relative "../test_runner"

class TestStudioTestRunner < Minitest::Test
  Status = Struct.new(:ok, :exitstatus) do
    def success? = ok
  end

  def test_parses_a_nonempty_minitest_summary
    assert_equal(
      { runs: 3, assertions: 7, failures: 0, errors: 0, skips: 1 },
      Studio::TestRunner.parse_summary("3 runs, 7 assertions, 0 failures, 0 errors, 1 skips\n")
    )
  end

  def test_accepts_a_clean_nonempty_run
    result = Studio::TestRunner.classify(
      "1 runs, 2 assertions, 0 failures, 0 errors, 0 skips\n",
      Status.new(true, 0)
    )

    assert_equal :pass, result.state
    assert_nil result.reason
  end

  def test_blocks_zero_run_summaries
    result = Studio::TestRunner.classify(
      "0 runs, 0 assertions, 0 failures, 0 errors, 0 skips\n",
      Status.new(true, 0)
    )

    assert_equal :blocked, result.state
    assert_equal "Minitest reported zero runs", result.reason
  end

  def test_blocks_missing_summaries
    result = Studio::TestRunner.classify("loaded successfully\n", Status.new(true, 0))

    assert_equal :blocked, result.state
    assert_equal "no valid Minitest summary", result.reason
  end

  def test_rejects_reported_failures_even_when_the_process_exits_zero
    result = Studio::TestRunner.classify(
      "1 runs, 2 assertions, 1 failures, 0 errors, 0 skips\n",
      Status.new(true, 0)
    )

    assert_equal :fail, result.state
    assert_equal "Minitest reported 1 failures and 0 errors", result.reason
  end

  def test_rejects_a_nonzero_process_with_a_clean_summary
    result = Studio::TestRunner.classify(
      "1 runs, 2 assertions, 0 failures, 0 errors, 0 skips\n",
      Status.new(false, 1)
    )

    assert_equal :fail, result.state
    assert_equal "test process exited 1", result.reason
  end
end
