# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "rbconfig"
require "stringio"
require "tmpdir"
require_relative "../../../lib/operator/dmesg"

class DmesgTest < Minitest::Test
  DMESG = File.expand_path("../../../lib/operator/dmesg.rb", __dir__)

  def test_identical_consecutive_lines_print_once_with_a_count
    assert_equal [ "Writing a.js ×3", "Writing b.js", "Writing a.js" ],
                 Operator::Dmesg.collapse([ "Writing a.js\n" ] * 3 + [ "Writing b.js\n", "Writing a.js\n" ])
  end

  def test_durations_read_as_seconds_then_minutes
    assert_equal "4.6s", Operator::Dmesg.duration(4.61)
    assert_equal "6m 12s", Operator::Dmesg.duration(372.2)
  end

  def test_findings_name_positions_and_verdicts_without_escapes
    output = "\e[1;35mRunning\e[0m\n.....F\nfallback_drift_lint: app/x.scss:12 var(--bg, #fff) drifts\n" \
             "noise\n1 runs, 1 failures\n"

    assert_equal [ "fallback_drift_lint: app/x.scss:12 var(--bg, #fff) drifts", "1 runs, 1 failures" ],
                 Operator::Dmesg.findings(output)
  end

  # A runner killed mid-suite prints dots and no verdict. Its last lines are the
  # evidence, so they stand in for findings rather than an empty list.
  def test_findings_fall_back_to_the_last_lines
    assert_equal [ "........", "......" ], Operator::Dmesg.findings("start\n....\n........\n......\n", limit: 2)
  end

  def test_escapes_only_at_a_terminal_that_did_not_ask_for_none
    tty = StringIO.new
    tty.define_singleton_method(:tty?) { true }

    assert Operator::Dmesg.escapes?(tty, {})
    refute Operator::Dmesg.escapes?(tty, { "NO_COLOR" => "1" })
    refute Operator::Dmesg.escapes?(StringIO.new, {})
  end

  # The known-bad run: one step passes loudly, one fails with a finding wrapped
  # in escapes, one passes with a warning. Only the failure, the warning and the
  # summary reach the operator; the passing step's output reaches the log.
  def test_a_run_prints_failures_warnings_and_one_summary
    out, log = run_ci do
      step "quiet_step", "echo passing-step-output"
      step "fallback_drift_lint", "printf '\\033[31mfallback_drift_lint: a.scss:3 drifts\\033[0m\\n'; exit 1"
      step "rubocop_autocorrect", "echo 'warn: rubocop autocorrected a.rb, not in git'"
    end
    lines = out.lines.map(&:chomp)

    assert_match(/\Aci0 at demo: fallback_drift_lint failed in \d+\.\ds\z/, lines[0])
    assert_equal "  fallback_drift_lint: a.scss:3 drifts", lines[1]
    assert_equal "ci0 at demo: rubocop_autocorrect warn: rubocop autocorrected a.rb, not in git", lines[2]
    assert_match(/\Aci0 at demo: 2 of 3 steps passed in \d+\.\ds; fallback_drift_lint failed\z/, lines[3])
    assert_match(%r{\Aci0 at demo: step output in /.+/ci\.log\z}, lines[4])
    assert_equal 5, lines.size, out
    refute_includes out, "passing-step-output"
    refute_includes out, "\e["
    assert_includes log, "passing-step-output"
  end

  def test_a_green_run_prints_one_line
    out, = run_ci { step "quiet_step", "echo fine" }

    assert_match(/\Aci0 at demo: 1 of 1 steps passed in \d+\.\ds\n\z/, out)
  end

  def test_a_command_that_cannot_start_is_a_failed_step
    out, = run_ci { step "missing_tool", "/nonexistent/pub4-ci-tool" }

    assert_includes out, "ci0 at demo: missing_tool failed in"
    assert_includes out, "0 of 1 steps passed"
  end

  # Rails' exit contract, kept: 1 when any step failed, nothing raised otherwise.
  def test_run_exits_one_on_failure_and_returns_on_success
    Dir.mktmpdir do |dir|
      error = assert_raises(SystemExit) do
        Operator::Dmesg::CiRun.run("demo", log: File.join(dir, "ci.log"), out: StringIO.new) { step "bad", "exit 3" }
      end
      assert_equal 1, error.status

      ran = Operator::Dmesg::CiRun.run("demo", log: File.join(dir, "ci.log"), out: StringIO.new) { step "good", "true" }
      assert ran.success?
    end
  end

  def test_the_zsh_entry_collapses_what_the_deploy_scripts_hand_it
    out, status = Open3.capture2(RbConfig.ruby, DMESG, "collapse", stdin_data: "Writing a\nWriting a\ndone\n")

    assert status.success?
    assert_equal "Writing a ×2\ndone\n", out
  end

  private

  def run_ci(&steps)
    Dir.mktmpdir do |dir|
      path = File.join(dir, "log", "ci.log")
      out = StringIO.new
      Operator::Dmesg::CiRun.new("demo", log: path, out:).perform(&steps)
      [ out.string, File.read(path) ]
    end
  end
end
