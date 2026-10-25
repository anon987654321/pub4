# frozen_string_literal: true

require "minitest/autorun"
require_relative "run_all"

class ContractRunnerContractTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def source
    @source ||= File.read(File.join(ROOT, "test", "run_all.rb"))
  end

  def test_contract_runner_isolated_per_file_uses_shared_bounded_capture
    assert_includes source, "Shared::Subprocess.capture2e"
    assert_includes source, "timeout: TIMEOUT"
    refute_includes source, "Open3.popen2e"
    refute_includes source, "Timeout.timeout"
    refute_includes source, "def kill_group"
  end

  def test_contract_runner_can_replay_passing_files_with_deterministic_seeds
    assert_includes source, 'REPLAY = Integer(ENV.fetch("CONTRACT_REPLAY", "0"))'
    assert_includes source, "Digest::SHA256.hexdigest"
    assert_includes source, %(["--seed", seed.to_s])
    assert_includes source, ":flake"
  end

  def test_flake_is_not_a_pass
    assert_includes source, "outcome.status == :pass && REPLAY.positive?"
    assert_includes source, "outcome.status != :pass"
  end
  class ExitStatus
    def initialize(success) = @success = success
    def success? = @success
  end

  def build_outcome(output, success: true)
    status = ExitStatus.new(success)
    Operator::ContractSuite.new.send(:build, "synthetic_test.rb", output, status)
  end

  def test_a_valid_nonzero_minitest_run_can_pass
    outcome = build_outcome("2 runs, 3 assertions, 0 failures, 0 errors, 0 skips\n")

    assert_equal :pass, outcome.status
    assert_equal 2, outcome.runs
    assert_equal 3, outcome.assertions
  end

  def test_a_zero_run_minitest_summary_is_not_a_pass
    outcome = build_outcome("0 runs, 0 assertions, 0 failures, 0 errors, 0 skips\n")

    assert_equal :fail, outcome.status
    assert_includes outcome.output, "Minitest reported zero runs"
  end

  def test_exit_zero_without_a_minitest_summary_is_not_a_pass
    outcome = build_outcome("loader exited without running tests\n")

    assert_equal :fail, outcome.status
    assert_includes outcome.output, "missing valid Minitest summary"
  end

  def test_failure_summary_cannot_pass_even_if_the_process_exits_zero
    outcome = build_outcome("1 runs, 1 assertions, 1 failures, 0 errors, 0 skips\n")

    assert_equal :fail, outcome.status
    assert_includes outcome.output, "Minitest reported 1 failures and 0 errors"
  end

end
