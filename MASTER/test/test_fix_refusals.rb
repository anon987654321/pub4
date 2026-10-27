# frozen_string_literal: true

require_relative "test_helper"
require "json"
require "fix/refusals"

# Every per-fix gate's refusal: a line, a row and a count, and never without a reason.
class TestFixRefusals < Minitest::Test
  Refusals = Master::Fix::Refusals

  def setup
    @dir = Dir.mktmpdir
    @previous = ENV["MASTER_FIX_REFUSALS_PATH"]
    ENV["MASTER_FIX_REFUSALS_PATH"] = File.join(@dir, "fix_refusals.jsonl")
    Refusals.begin_run!
  end

  def teardown
    ENV["MASTER_FIX_REFUSALS_PATH"] = @previous
    FileUtils.rm_rf(@dir)
    Refusals.begin_run!
  end

  def rows = File.readlines(Refusals.log_path).map { |line| JSON.parse(line) }

  def test_a_refusal_prints_one_line_writes_one_row_and_counts_its_gate
    out, = capture_io do
      Refusals.record(gate: :scope, file: "/repo/MASTER/lib/a.rb", reason: "changes lines 90-91, finding range is 1-35",
                      law: "FEW_ARGUMENTS", root: "/repo")
    end

    assert_equal "fix0: MASTER/lib/a.rb refused by scope: changes lines 90-91, finding range is 1-35\n", out
    row = rows.last
    assert_equal %w[scope MASTER/lib/a.rb FEW_ARGUMENTS], row.values_at("gate", "file", "law")
    assert_equal 1, Refusals.counts[:scope]
  end

  def test_an_empty_reason_with_no_exception_is_the_gates_defect_and_raises
    assert_raises(Refusals::MissingReason) { Refusals.record(gate: :verifier, file: "a.rb", reason: "  ") }
    assert_raises(Refusals::MissingReason) { Refusals.record(gate: :verifier, file: "a.rb") }
    refute File.exist?(Refusals.log_path), "a refusal with no reason writes nothing"
  end

  def test_an_empty_reason_is_filled_from_the_exception
    error = Encoding::CompatibilityError.new("incompatible character encodings: UTF-8 and BINARY")
    capture_io { Refusals.record(gate: :verifier, file: "a.rb", reason: "", error:) }

    assert_equal "Encoding::CompatibilityError: incompatible character encodings: UTF-8 and BINARY", rows.last["reason"]
    assert_equal rows.last["reason"], rows.last["error"]
  end

  def test_a_reason_and_an_exception_are_both_kept
    error = RuntimeError.new("quorum lost")
    capture_io { Refusals.record(gate: :consensus, file: "a.rb", reason: "the panel refused it", error:) }

    assert_equal "the panel refused it (RuntimeError: quorum lost)", rows.last["reason"]
  end

  def test_the_pass_summary_names_every_gate_and_starts_a_fresh_count
    capture_io do
      2.times { Refusals.record(gate: :scope, file: "a.rb", reason: "too wide") }
      Refusals.record(gate: :lint, file: "a.rb", reason: "house_lint")
      Refusals.record(gate: :odd_gate, file: "a.rb", reason: "x")
    end

    line = Refusals.pass_summary_line
    assert_match(/\Afix0: refusals this pass: budget=0 scope=2 verifier=0 /, line)
    assert_includes line, " lint=1 "
    assert line.end_with?(" odd_gate=1"), "a gate not in the list still counts"
    assert_empty Refusals.counts
  end

  def test_the_log_rotates_past_its_limit
    File.write(Refusals.log_path, "x" * (Refusals::MAX_BYTES + 1))
    capture_io { Refusals.record(gate: :scope, file: "a.rb", reason: "too wide") }

    assert_equal 1, rows.size
    assert_equal 1, Dir.glob("#{Refusals.log_path}.*").reject { |path| path.end_with?(".lock") }.size
  end
end
