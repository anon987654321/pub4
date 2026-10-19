# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/operator/check_runner"
require "rbconfig"

class TestCheckRunnerStdin < Minitest::Test
  def test_noninteractive_step_receives_eof
    runner = Operator::CheckRunner.new(
      prefix: "check-runner-test",
      root: File.expand_path("../..", __dir__),
      timeout: 2,
      quiet: true
    )

    assert runner.run(
      "stdin eof",
      RbConfig.ruby,
      "-e",
      "exit(STDIN.read.empty? ? 0 : 1)"
    )
  end
end
