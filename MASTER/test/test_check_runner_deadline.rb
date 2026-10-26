# frozen_string_literal: true

require_relative "test_helper"
require "open3"
require "pathname"

# A script check that never returns used to hold the whole check ladder.
class TestCheckRunnerDeadline < Minitest::Test
  RUNNER = File.expand_path("../checks/runner.rb", __dir__)

  def test_a_hung_script_check_fails_at_its_deadline
    Dir.mktmpdir do |dir|
      script = File.join(dir, "hang.rb")
      File.write(script, "sleep 60\n")
      relative = Pathname.new(script).relative_path_from(File.dirname(RUNNER)).to_s
      checks = File.join(dir, "checks.yml")
      File.write(checks, "hung_check:\n  script: #{relative}\n  timeout_seconds: 1\n")
      env = { "CHECKS_FILE" => checks, "CHECK_LEDGER" => File.join(dir, "ledger.jsonl") }

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      out, status = Open3.capture2e(env, RbConfig.ruby, RUNNER, "--all")

      assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 30
      refute status.success?, out
      assert_includes out, "hang.rb timed out after 1s"
    end
  end
end
