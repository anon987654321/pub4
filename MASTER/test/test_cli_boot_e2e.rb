# frozen_string_literal: true

require_relative "test_helper"
require "tempfile"

class TestCliBootE2e < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  CLI = File.join(ROOT, "bin", "cli")
  COMMAND_TIMEOUT = 45
  BOOT_ENV = {
    "MASTER_FAST" => "1",
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

  def run(*args)
    Minitest::Test.instance_method(:run_without_timeout).bind_call(self, *args)
  end

  def test_pipe_status_command
    out, err, status = run_cli_pipe("/status\n")
    combined = "#{out}#{err}"
    assert status.success?, "cli pipe failed: #{combined[0, 400]}"
    refute combined.strip.empty?, "expected /status output"
  end

  def test_pipe_help_command
    out, err, status = run_cli_pipe("/help\n")
    combined = "#{out}#{err}"
    assert status.success?, "cli /help failed: #{combined[0, 400]}"
    assert_match(/help|command/i, combined)
  end

  private

  def run_cli_pipe(input)
    out = Tempfile.new("master-cli-out")
    err = Tempfile.new("master-cli-err")
    read_io, write_io = IO.pipe
    pid = Process.spawn(
      BOOT_ENV,
      Master::BUNDLE_BIN, "exec", "ruby", CLI,
      chdir: ROOT,
      in: read_io,
      out: out.path,
      err: err.path,
    )
    read_io.close
    write_io.write(input)
    write_io.close
    wait_for_cli(pid, out, err)
  ensure
    read_io&.close unless read_io&.closed?
    write_io&.close unless write_io&.closed?
    out&.close!
    err&.close!
  end

  def wait_for_cli(pid, out, err)
    deadline = Time.now + COMMAND_TIMEOUT
    loop do
      done_pid, status = Process.waitpid2(pid, Process::WNOHANG)
      return [File.read(out.path), File.read(err.path), status] if done_pid
      raise_timeout(pid, out, err) if Time.now >= deadline

      sleep 0.1
    end
  end

  def raise_timeout(pid, out, err)
    Process.kill("TERM", pid)
    sleep 0.5
    Process.kill("KILL", pid)
  rescue Errno::ESRCH
    # Child exited between timeout detection and cleanup.
  ensure
    raise Timeout::Error,
          "cli pipe timed out after #{COMMAND_TIMEOUT}s\nstdout:\n#{File.read(out.path)[0, 400]}\nstderr:\n#{File.read(err.path)[0, 400]}"
  end
end
