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
      err: err.path
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

# The REPL on a real terminal, because the exit path only exists there: Reline
# owns the line, ^C arrives as SIGINT through the terminal driver, and ^D as an
# end of file. Every ^C in the 2026-09-13 sessions was the operator trying to
# leave, and the CLI answered "^C again to quit" and then crashed. Not gated
# with the pipe tests above: leaving is the one thing a session must never get
# wrong.
class TestCliReplExit < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  ENV_FOR_PTY = TestCliBootE2e::BOOT_ENV.merge(
    "MASTER_FAST" => "0", "MASTER_SKIP_BOOT_SCAN" => "1", "MASTER_SKIP_TTS" => "1", "TERM" => "xterm",
  ).freeze
  READY = /% |\$ /

  def test_timeout = 60

  def test_ctrl_c_at_the_prompt_exits_cleanly
    output, status = drive { |terminal| terminal.write("\x03") }

    assert_equal 0, status.exitstatus, output
    refute_match(/Error|from .+\.rb:\d+/, output)
  end

  def test_ctrl_d_at_the_prompt_exits_cleanly
    output, status = drive { |terminal| terminal.write("\x04") }

    assert_equal 0, status.exitstatus, output
    refute_match(/Error|from .+\.rb:\d+/, output)
  end

  private

  def drive
    require "pty"
    output = +""
    PTY.spawn(ENV_FOR_PTY, Master::BUNDLE_BIN, "exec", "ruby", "bin/cli", chdir: ROOT) do |reader, writer, pid|
      read_until(reader, output, READY, 30)
      sleep 0.5
      yield writer
      read_until(reader, output, nil, 10)
      _, status = Process.waitpid2(pid)
      return [output, status]
    end
  end

  def read_until(reader, output, pattern, seconds)
    deadline = Time.now + seconds
    while Time.now < deadline
      break if pattern && output.match?(pattern)
      next unless reader.wait_readable(0.2)

      output << reader.readpartial(4096)
    end
  rescue Errno::EIO, EOFError
    output
  end
end
