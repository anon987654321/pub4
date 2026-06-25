# frozen_string_literal: true

require_relative "test_helper"
require "open3"

class TestCliBootE2e < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  CLI = File.join(ROOT, "bin", "cli")
  BOOT_ENV = {
    "MASTER_SAFE_MODE" => "1",
    "MASTER_WEB" => "0",
    "MASTER_BACKGROUND" => "0",
    "MASTER_AUTOFIX" => "0",
    "MASTER_WATCH" => "0",
    "MASTER_WATCHER" => "0",
    "MASTER_HEARTBEAT" => "0",
    "MASTER_STRICT_BOOT" => "0",
  }.freeze

  def setup
    skip "set MASTER_CLI_E2E=1 to run subprocess boot tests" unless ENV["MASTER_CLI_E2E"] == "1"
  end

  def run_without_timeout(*args)
    Minitest::Test.instance_method(:run_without_timeout).bind_call(self, *args)
  end

  def test_pipe_status_command
    out, err, status = Timeout.timeout(120) do
      Open3.capture3(BOOT_ENV, Master::BUNDLE_BIN, "exec", "ruby", CLI, chdir: ROOT, stdin_data: "/status\n")
    end
    combined = "#{out}#{err}"
    assert status.success?, "cli pipe failed: #{combined[0, 400]}"
    refute combined.strip.empty?, "expected /status output"
  end

  def test_pipe_help_command
    out, err, status = Timeout.timeout(120) do
      Open3.capture3(BOOT_ENV, Master::BUNDLE_BIN, "exec", "ruby", CLI, chdir: ROOT, stdin_data: "/help\n")
    end
    combined = "#{out}#{err}"
    assert status.success?, "cli /help failed: #{combined[0, 400]}"
    assert_match(/help|command/i, combined)
  end
end