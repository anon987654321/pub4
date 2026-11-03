# frozen_string_literal: true

require_relative "test_helper"
require "open3"
require "pathname"

# A script check that never returns used to hold the whole check ladder.
class TestCheckRunnerDeadline < Minitest::Test
  RUNNER = File.expand_path("../checks/runner.rb", __dir__)

  def test_a_hung_script_check_fails_at_its_deadline
    Dir.mktmpdir do |dir|
      # The registry refuses parent and absolute script paths and resolves
      # scripts against the runner's own directory, so the hung script is
      # registered from there and removed when the assertion ends.
      hung = File.join(File.dirname(RUNNER), "hang.rb")
      File.write(hung, "sleep 60\n")
      begin
        checks = File.join(dir, "checks.yml")
        File.write(checks, "hung_check:\n  script: hang.rb\n  timeout_seconds: 1\n")
        env = { "CHECKS_FILE" => checks, "CHECK_LEDGER" => File.join(dir, "ledger.jsonl") }

        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        out, status = Open3.capture2e(env, RbConfig.ruby, RUNNER, "--all")

        assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 30
        refute status.success?, out
        assert_includes out, "hang.rb timed out after 1s"
      ensure
        File.delete(hung)
      end
    end
  end
end
