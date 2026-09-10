# frozen_string_literal: true

require_relative "test_helper"

class TestOutputGuard < Minitest::Test
  def setup
    @guard = Master::Voice::OutputGuard.new
  end

  def issues(text, context: :routine)
    result = @guard.validate(text, context:)
    result.ok? ? [] : result.message.split("; ")
  end

  def test_preserves_multi_line_diagnostic_output
    text = "scan: lib/foo.rb 2 violation(s)\nscan: lib/bar.rb 0 violation(s)"
    result = @guard.validate(text, context: :diagnostic)
    assert result.ok?, result.err? ? result.message : result.value!.to_s
  end

  def test_rejects_completion_claim_without_evidence
    result = @guard.validate("Task completed successfully.", context: :completion)
    refute result.ok?
    assert_match(/completion claim/, result.message)
  end

  def test_accepts_completion_with_command_output
    text = "Task done.\n$ ruby -Itest test/foo.rb\n0 failures"
    result = @guard.validate(text, context: :completion)
    assert result.ok?, result.err? ? result.message : result.value!.to_s
  end

  def test_accepts_modification_with_diff
    text = "Changed file.\n```diff\n+line\n```"
    result = @guard.validate(text, context: :modification)
    assert result.ok?, result.err? ? result.message : result.value!.to_s
  end

  def test_rejects_collapsed_boot_banner
    result = @guard.validate("master: one line only", context: :boot)

    refute result.ok?
    assert_match(/5-line/, result.message)
  end

  def test_accepts_five_line_boot_banner
    text = [
      "master: boot safe=1 web=0",
      "master: background=0 watch=0",
      "master: loop=none owner=none",
      "master: budget valid=true slot=unknown",
      "master: ready dmesg=preserved",
    ].join("\n")

    assert @guard.validate(text, context: :boot).ok?
  end

  def test_rejects_help_without_detail
    result = @guard.validate("/scan - deep scan files", context: :help)

    refute result.ok?
    assert_match(/help output/, result.message)
  end

  # Ground::Tool::Protocol's third requirement. The pair matters: the fence on
  # its own is a code sample, and the past-tense claim on its own is covered by
  # the completion check.
  def test_rejects_a_shell_block_offered_as_execution
    result = @guard.validate("I ran the suite.\n```sh\nrake test\n```", context: :routine)

    refute result.ok?
    assert_match(/shell block presented as execution/, result.message)
  end

  def test_accepts_a_shell_block_with_a_real_transcript
    text = "I ran the suite.\n```sh\n$ rake test\n2227 runs, 0 failures\n```"

    refute_includes issues(text), "shell block presented as execution"
  end

  def test_accepts_a_shell_block_offered_for_the_operator_to_run
    text = "Run this yourself:\n```sh\nrake test\n```"

    refute_includes issues(text), "shell block presented as execution"
  end

  def test_rejects_minimize_applied_to_diagnostics
    result = @guard.validate("Minimize diagnostic output into one short line.", context: :routine)

    refute result.ok?
    assert_match(/minimize rule/, result.message)
  end
end
