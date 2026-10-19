# frozen_string_literal: true

require "minitest/autorun"
require "rbconfig"
require_relative "../lib/check_runner"

class TestCheckRunnerStdin < Minitest::Test
  def test_noninteractive_step_receives_eof
    runner = Deploy::CheckRunner.new(
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
