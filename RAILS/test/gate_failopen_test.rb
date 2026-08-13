# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "rbconfig"
require "tmpdir"
require "json"
require_relative "../../OPENBSD/lib/gate_result"
require_relative "../../OPENBSD/lib/gate_ledger"

# A gate that breaks must not decide anything, and must not disappear.
#
# arXiv 2607.07405 audits its own four-gate suite and finds one gate blocking at
# 100% precision over 161 fires and another at 5%, which is why its harness
# "records the error and allows the original call" when a gate raises: a gate
# whose blocks are mostly its own bugs teaches people to route around the suite.
#
# pub4's version was worse than a false block. RAILS/gates/runner.rb built its
# whole outcome table in one `to_h`, with `klass.run` unguarded inside it, so a
# single raising gate ended the process — every gate after it in --all order
# never ran, and the summary was a backtrace. Measured against the committed
# runner before the fix, with the fixture registry below: it died at gate 2 of 4.
#
# Fail-open on its own would only move the failure somewhere quieter, so the two
# halves are tested together. Deploy::GateLedger is what stops a crashed gate
# being silently absent forever, and this asserts it names the gate rather than
# just counting it.
class GateFailOpenTest < Minitest::Test
  GATES_DIR = File.expand_path("../gates", __dir__)
  RUNNER = File.join(GATES_DIR, "runner.rb")
  FIXTURE_REGISTRY = File.join(GATES_DIR, "fixtures", "failopen", "gates.yml")

  def run_fixture_suite(env = {})
    Dir.mktmpdir("gate-failopen") do |dir|
      ledger = File.join(dir, "ledger.jsonl")
      out, status = Open3.capture2e(
        { "GATES_FILE" => FIXTURE_REGISTRY, "GATE_LEDGER" => ledger }.merge(env),
        RbConfig.ruby, RUNNER, "--all"
      )
      yield out, status, Deploy::GateLedger.new(path: ledger)
    end
  end

  # The one that matters. ok_after is declared after the raising gate, so it only
  # appears in the output if the run survived the crash.
  def test_a_raising_gate_does_not_stop_the_gates_after_it
    run_fixture_suite do |out, status, _ledger|
      assert_includes out, "ok_before PASSED", out
      assert_includes out, "raiser ERRORED", out
      assert_includes out, "ok_after PASSED", "a gate after the raising one never ran:\n#{out}"
      assert_equal 0, status.exitstatus, "a crashed gate must not block by default:\n#{out}"
    end
  end

  # NameError from a renamed class and NoMethodError from a refactor are the two
  # shapes this has actually taken. Both must land as :errored, not :failed.
  def test_a_missing_gate_class_errors_rather_than_failing
    run_fixture_suite do |out, _status, _ledger|
      assert_includes out, "missing_class ERRORED", out
      assert_includes out, "uninitialized constant", out
    end
  end

  # The summary is the line people quote. It may not claim a gate count the run
  # did not earn, and it may not bury the errored gates in a pass total.
  def test_the_summary_names_the_errored_gates_and_does_not_count_them_as_passes
    run_fixture_suite do |out, _status, _ledger|
      assert_includes out, "2 gate(s) ERRORED and blocked nothing: raiser, missing_class", out
      refute_includes out, "ALL SELECTED GATES PASSED", out
      assert_includes out, "2 gate(s) passed, 2 errored", out
    end
  end

  # The deploy host wants the other policy: a gate that cannot run is itself the
  # news, and the run should stop.
  def test_strict_errors_promotes_a_crash_to_a_blocking_failure
    run_fixture_suite("GATE_STRICT_ERRORS" => "1") do |out, status, _ledger|
      assert_includes out, "SOME GATES FAILED", out
      assert_includes out, "raiser", out
      assert_equal 1, status.exitstatus, out
    end
  end

  # Fail-open without a record is how a broken gate goes unguarded for weeks.
  def test_the_ledger_records_every_gate_of_the_run_by_name_and_outcome
    run_fixture_suite do |_out, _status, ledger|
      rows = ledger.summary
      by_gate = rows.to_h { |r| [r[:gate], r] }

      assert_equal %w[missing_class ok_after ok_before raiser], by_gate.keys.sort
      assert_equal 1, by_gate.fetch("raiser")[:errored]
      assert_equal 1, by_gate.fetch("ok_after")[:passed]
      assert_equal 1, ledger.entries.map { |e| e["run"] }.uniq.size,
                   "every gate of one invocation must share a run id, or per-run and per-gate cannot be told apart"
    end
  end

  # min_runs exists so one bad afternoon does not read as a chronic gate. The
  # flag has to fire on a real history and stay quiet on a short one.
  def test_the_ledger_flags_a_gate_that_keeps_erroring_and_ignores_a_short_history
    Dir.mktmpdir("gate-ledger") do |dir|
      ledger = Deploy::GateLedger.new(path: File.join(dir, "l.jsonl"))
      4.times { |i| ledger.record(gate: "flaky", outcome: :errored, run_id: "r#{i}") }

      assert_empty ledger.flags, "4 runs is below min_runs — a flag here would be noise"

      2.times { |i| ledger.record(gate: "flaky", outcome: :errored, run_id: "r#{i + 4}") }
      assert_match(/flaky: errored on 6\/6 runs/, ledger.flags.join("\n"))
    end
  end

  # The ledger observes; it must never be the thing that takes a run down, which
  # would make the audit mechanism the top source of false blocks.
  def test_a_ledger_that_cannot_be_written_warns_instead_of_raising
    ledger = Deploy::GateLedger.new(path: File.join(Dir.tmpdir, "no-such-dir-#{Process.pid}", "l.jsonl"))

    _out, err = capture_io do
      assert_same ledger, ledger.record(gate: "x", outcome: :passed, run_id: "r")
    end
    assert_match(/ledger write failed/, err)
  end

  # GateResult's own contract, independent of the runner.
  def test_errored_outcome_ranks_above_inconclusive_and_never_reads_as_a_pass
    result = Deploy::GateResult.new
    result.errored!("boom")

    assert_predicate result, :errored?
    assert_equal :errored, result.outcome
    assert_predicate result, :ok?, "fail-open: an errored gate records no failure by default"
    assert_empty result.failures
  end

  # A composite that swallows a crashed leaf is the same false green one level up.
  def test_a_composite_carries_its_leafs_error_rather_than_reporting_passed
    leaf = Deploy::GateResult.new.errored!("leaf broke")
    composite = Deploy::GateResult.new
    composite.checked!(10)
    composite.merge!(leaf, label: "leaf")

    assert_equal :errored, composite.outcome
    assert_includes composite.errors.first, "[leaf] leaf broke"
  end
end
