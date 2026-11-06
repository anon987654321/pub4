# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "rbconfig"
require "tmpdir"
require "json"
require_relative "../../OPENBSD/lib/check_result"
require_relative "../../OPENBSD/lib/check_ledger"

# A crashing check remains a distinct error outcome, but it cannot
# contribute to a successful run. The runner must continue through the registry,
# record the failed instrument in its ledger, and exit non-zero after reporting
# every check. This keeps diagnostics complete without turning a crash into green.
class CheckFailOpenTest < Minitest::Test
  CHECKS_DIR = File.expand_path("../../MASTER/checks", __dir__)
  RUNNER = File.join(CHECKS_DIR, "runner.rb")
  FIXTURE_REGISTRY = File.join(CHECKS_DIR, "fixtures", "failopen", "checks.yml")

  def run_fixture_suite(env = {})
    Dir.mktmpdir("check-failopen") do |dir|
      ledger = File.join(dir, "ledger.jsonl")
      out, status = Open3.capture2e(
        { "CHECKS_FILE" => FIXTURE_REGISTRY, "CHECK_LEDGER" => ledger }.merge(env),
        RbConfig.ruby, RUNNER, "--all"
      )
      retired = File.read(File.join(dir, ".check_output.log")) if File.file?(File.join(dir, ".check_output.log"))
      yield out, status, Deploy::CheckLedger.new(path: ledger), retired.to_s
    end
  end

  # The run's closing line, in the shape Operator::CheckChain and the /fix proof parse.
  def summary_line(counts, tail)
    /^checks0 at rails: #{counts} in \S+, autofix (?:on|off); #{Regexp.escape(tail)}$/
  end

  # The one that matters. ok_after is declared after the raising check, so it only
  # reaches the retired-output log if the run survived the crash. A passing check
  # prints nothing, so the log beside the ledger is where it has to be found.
  def test_a_raising_check_does_not_stop_the_checks_after_it
    run_fixture_suite do |out, status, _ledger, retired|
      assert_includes retired, "checks0 at rails: ok_before passed", out
      assert_includes out, "checks0 at rails: raiser errored, run cannot pass", out
      assert_includes retired, "checks0 at rails: ok_after passed", "a check after the raising one never ran:\n#{out}"
      refute_includes out, "ok_after passed", "a passing check printed to the terminal:\n#{out}"
      assert_equal 1, status.exitstatus, "an errored check cannot make the run successful:\n#{out}"
    end
  end

  # NameError from a renamed class and NoMethodError from a refactor are the two
  # shapes this has actually taken. Both must land as :errored, not :failed.
  def test_a_missing_check_class_errors_and_blocks_the_run
    run_fixture_suite do |out, status, _ledger|
      assert_includes out, "missing_class errored, run cannot pass", out
      assert_includes out, "uninitialized constant", out
      assert_equal 1, status.exitstatus, out
    end
  end

  # The summary is the line people quote. It may not claim a check count the run
  # did not earn, and it may not bury the errored checks in a pass total.
  def test_the_summary_names_the_errored_checks_and_does_not_count_them_as_passes
    run_fixture_suite do |out, _status, _ledger|
      # Autofix follows the caller's CHECK_AUTOFIX, which this test does not set.
      assert_match(summary_line("2 pass, 0 fail, 0 skip, 0 inconclusive, 2 error", "errored=raiser,missing_class"), out)
    end
  end

  # The former opt-out is inert: a caller cannot turn a crash into a pass.
  def test_errored_checks_block_even_when_legacy_opt_out_is_set
    run_fixture_suite("CHECK_STRICT_ERRORS" => "0") do |out, status, _ledger|
      assert_match(summary_line("2 pass, 0 fail, 0 skip, 0 inconclusive, 2 error", "errored=raiser,missing_class"), out)
      assert_equal 1, status.exitstatus, out
    end
  end

  # The ledger keeps the error named and attributable even when the overall run
  # correctly exits non-zero.
  def test_the_ledger_records_every_check_of_the_run_by_name_and_outcome
    run_fixture_suite do |_out, _status, ledger|
      rows = ledger.summary
      by_check = rows.to_h { |r| [r[:check], r] }

      assert_equal %w[missing_class ok_after ok_before raiser], by_check.keys.sort
      assert_equal 1, by_check.fetch("raiser")[:errored]
      assert_equal 1, by_check.fetch("ok_after")[:passed]
      assert_equal 1, ledger.entries.map { |e| e["run"] }.uniq.size,
                   "every check of one invocation must share a run id, or per-run and per-check cannot be told apart"
    end
  end

  # min_runs exists so one bad afternoon does not read as a chronic check. The
  # flag has to fire on a real history and stay quiet on a short one.
  def test_the_ledger_flags_a_check_that_keeps_erroring_and_ignores_a_short_history
    Dir.mktmpdir("check-ledger") do |dir|
      ledger = Deploy::CheckLedger.new(path: File.join(dir, "l.jsonl"))
      4.times { |i| ledger.record(check: "flaky", outcome: :errored, run_id: "r#{i}") }

      assert_empty ledger.flags, "4 runs is below min_runs — a flag here would be noise"

      2.times { |i| ledger.record(check: "flaky", outcome: :errored, run_id: "r#{i + 4}") }
      assert_match(/flaky: errored on 6\/6 runs/, ledger.flags.join("\n"))
    end
  end

  # The ledger observes; it must never be the thing that takes a run down, which
  # would make the audit mechanism the top source of false blocks.
  def test_a_ledger_that_cannot_be_written_warns_instead_of_raising
    ledger = Deploy::CheckLedger.new(path: File.join(Dir.tmpdir, "no-such-dir-#{Process.pid}", "l.jsonl"))

    _out, err = capture_io do
      assert_same ledger, ledger.record(check: "x", outcome: :passed, run_id: "r")
    end
    assert_match(/ledger write failed/, err)
  end

  # CheckResult's own contract, independent of the runner.
  def test_errored_outcome_ranks_above_inconclusive_and_is_not_ok
    result = Deploy::CheckResult.new
    result.errored!("boom")

    assert_predicate result, :errored?
    assert_equal :errored, result.outcome
    refute_predicate result, :ok?, "a check without a verdict is not ok"
    assert_empty result.failures
  end

  def test_report_exits_nonzero_for_an_errored_check
    result = Deploy::CheckResult.new.errored!("boom")

    error = assert_raises(SystemExit) do
      capture_io { result.report!("should not print success") }
    end
    assert_equal 1, error.status
  end

  # A composite that swallows a crashed leaf is the same false green one level up.
  def test_a_composite_carries_its_leafs_error_rather_than_reporting_passed
    leaf = Deploy::CheckResult.new.errored!("leaf broke")
    composite = Deploy::CheckResult.new
    composite.checked!(10)
    composite.merge!(leaf, label: "leaf")

    assert_equal :errored, composite.outcome
    assert_includes composite.errors.first, "[leaf] leaf broke"
  end
end
