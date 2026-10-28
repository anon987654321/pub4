# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/operator/check_runner"
require "rbconfig"

class TestCheckRunnerStdin < Minitest::Test
  def test_timeout_preserves_partial_output_and_reports_failure
    runner = Operator::CheckRunner.new(
      prefix: "check-runner-timeout",
      root: File.expand_path("../..", __dir__),
      timeout: 0.1,
      quiet: true,
    )

    refute runner.run(
      "bounded timeout",
      RbConfig.ruby,
      "-e",
      "STDOUT.sync = true; puts 'started'; sleep 30",
    )

    output = runner.results.fetch(0).output
    assert_includes output, "started"
    assert_includes output, "step timed out after"
  end

  def test_noninteractive_step_receives_eof
    runner = Operator::CheckRunner.new(
      prefix: "check-runner-test",
      root: File.expand_path("../..", __dir__),
      timeout: 2,
      quiet: true,
    )

    assert runner.run(
      "stdin eof",
      RbConfig.ruby,
      "-e",
      "exit(STDIN.read.empty? ? 0 : 1)",
    )
  end
end
