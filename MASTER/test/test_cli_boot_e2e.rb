# frozen_string_literal: true

require_relative "test_helper"
require "tempfile"
require "tmpdir"
require "fileutils"
require "pty"

class TestCliBootE2e < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  CLI = File.join(ROOT, "bin", "master")
  COMMAND_TIMEOUT = 45
  # The booted child keeps the Ruby that runs this test: the entrypoint would
  # otherwise re-exec into another installed Ruby that inherits this process's
  # BUNDLE_PATH and cannot load gems built against this Ruby's libruby.
  BOOT_ENV = {
    "MASTER_RUBY_REEXEC_DONE" => "1",
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
    @lock_dir = Dir.mktmpdir("master-e2e-lock-")
  end

  def teardown
    FileUtils.remove_entry(@lock_dir) if @lock_dir
  end

  # A live daemon's inherited lock fd owns MASTER/.master/process.lock, and the
  # booted child sees a busy flock it did nothing to earn — so each test boots
  # against its own tmpdir lock through MASTER_PROCESS_LOCK_PATH.
  def boot_env(extra = {})
    BOOT_ENV.merge("MASTER_PROCESS_LOCK_PATH" => File.join(@lock_dir, "process.lock")).merge(extra)
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
    assert_match(/help0 at master0:/i, combined)
    assert_match(%r{/fix is the primary repair operation in the interactive console}, combined)
  end

  def test_bin_ruby_wrapper_reaches_master_boot
    output = +""
    env = boot_env
    PTY.spawn(env, File.join(ROOT, "bin", "ruby"), CLI, "--fast", chdir: ROOT) do |reader, writer, pid|
      writer.close
      deadline = Time.now + COMMAND_TIMEOUT
      status = nil

      while Time.now < deadline
        begin
          output << reader.readpartial(4096) if reader.wait_readable(0.2)
        rescue Errno::EIO, EOFError
          done, status = Process.waitpid2(pid)
          break if done
        end

        done, status = Process.waitpid2(pid, Process::WNOHANG)
        break if done
      end

      unless status
        Process.kill("TERM", pid)
        Process.wait(pid)
        flunk "bin/ruby cli boot timed out: #{output[0, 1000]}"
      end

      assert status.success?, "bin/ruby cli boot failed: #{output[0, 1000]}"
      assert_match(/master: .*posture|boot0:/, output)
    ensure
      writer&.close unless writer&.closed?
      reader&.close unless reader&.closed?
    end
  end

  def test_tty_fast_boot_reaches_master_boot
    output = +""
    env = boot_env
    PTY.spawn(env, Master::BUNDLE_BIN, "exec", "ruby", CLI, chdir: ROOT) do |reader, writer, pid|
      writer.close
      deadline = Time.now + COMMAND_TIMEOUT
      status = nil

      while Time.now < deadline
        begin
          output << reader.readpartial(4096) if reader.wait_readable(0.2)
        rescue Errno::EIO, EOFError
          done, status = Process.waitpid2(pid)
          break if done
        end

        done, status = Process.waitpid2(pid, Process::WNOHANG)
        break if done
      end

      unless status
        Process.kill("TERM", pid)
        Process.wait(pid)
        flunk "cli fast tty boot timed out: #{output[0, 1000]}"
      end

      assert status.success?, "cli fast tty boot failed: #{output[0, 1000]}"
      assert_match(/master: .*posture|boot0:/, output)
    ensure
      writer&.close unless writer&.closed?
      reader&.close unless reader&.closed?
    end
  end

  private

  def run_cli_pipe(input)
    out = Tempfile.new("master-cli-out")
    err = Tempfile.new("master-cli-err")
    read_io, write_io = IO.pipe
    pid = Process.spawn(
      boot_env,
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
  # These PTY cases exercise the same Reline prompt used by bare bin/master;
  # the face is printed above it and never owns terminal input.
  ENV_FOR_PTY = TestCliBootE2e::BOOT_ENV.merge(
    "MASTER_FAST" => "0", "MASTER_SKIP_BOOT_SCAN" => "1", "MASTER_SKIP_TTS" => "1", "TERM" => "xterm",
    "MASTER_FACE_AUTO_MIC" => "0"
  ).freeze
  READY = /\S+:\S+\$ /

  # A real model call under rate-limited/failover conditions can run well
  # past the 30s boot+reply windows below; 150s gives the chitchat test
  # headroom without loosening the two fast ^C/^D tests.
  def test_timeout = 150

  def setup
    @lock_dir = Dir.mktmpdir("master-e2e-lock-")
  end

  def teardown
    FileUtils.remove_entry(@lock_dir) if @lock_dir
  end

  # Same reason as TestCliBootE2e: the live lock on the checkout can flake a
  # boot that would otherwise succeed, so the PTY boots take their own tmpdir
  # lock through MASTER_PROCESS_LOCK_PATH.
  def boot_env
    ENV_FOR_PTY.merge("MASTER_PROCESS_LOCK_PATH" => File.join(@lock_dir, "process.lock"))
  end

  # One ^C clears the line, as zsh does; the second inside the window closes.
  # The pause is for the prompt to re-arm: a ^C written while Reline is between
  # two readline calls is read as input rather than raising.
  def test_ctrl_c_at_the_prompt_exits_cleanly
    output, status = drive { |terminal| 2.times { write_terminal(terminal, "\x03"); sleep 1.2 } }

    assert_equal 0, status.exitstatus, output
    refute_match(/Error|from .+\.rb:\d+/, output)
  end

  def test_ctrl_d_at_the_prompt_exits_cleanly
    output, status = drive { |terminal| write_terminal(terminal, "\x04") }

    assert_equal 0, status.exitstatus, output
    refute_match(/Error|from .+\.rb:\d+/, output)
  end

  # Bare entry must show the face projection without taking keyboard ownership.
  # /face refreshes that projection in place; Ctrl-D exits the one Reline session.
  def test_bare_entry_keeps_the_canonical_prompt_beneath_the_face_overlay
    require "pty"
    output = +""
    status = nil
    completed = false
    marker = "face0 at master0: visual layer refreshed; Reline owns input"
    PTY.spawn(boot_env, Master::BUNDLE_BIN, "exec", "ruby", "bin/master", chdir: ROOT) do |reader, writer, pid|
      begin
        read_until(reader, output, READY, 30)
        assert_match(READY, output, "CLI never showed its working Reline prompt")
        assert_includes output, marker, "bare startup did not render the face layer"
        refute_match(/\e\[\?1049h/, output, "bare startup must not take over the alternate screen")

        previous_count = output.scan(marker).length
        writer.write("/face\n")
        deadline = Time.now + 8
        loop do
          marker_at = output.rindex(marker)
          prompt_after_overlay = marker_at && output[(marker_at + marker.length)..].to_s.match?(READY)
          break if output.scan(marker).length > previous_count && prompt_after_overlay
          break if Time.now >= deadline

          output << reader.readpartial(4096) if reader.wait_readable(0.2)
        end
        assert_operator output.scan(marker).length, :>, previous_count, "/face did not redraw the in-place overlay"
        marker_at = output.rindex(marker)
        assert_match(READY, output[(marker_at + marker.length)..].to_s,
                     "/face did not return to the same working prompt")
        refute_match(/\e\[\?1049h/, output, "/face must not switch terminal input modes")

        writer.write("\x04")
        deadline = Time.now + 10
        loop do
          done, status = Process.waitpid2(pid, Process::WNOHANG)
          break if done

          if reader.wait_readable(0.2)
            begin
              output << reader.readpartial(4096)
            rescue Errno::EIO, EOFError
              # The PTY can close just before waitpid observes the exited child.
            end
          end
          flunk "CLI did not exit after Ctrl-D: #{output[-1200, 1200]}" if Time.now >= deadline
        end
        completed = true
      ensure
        unless completed
          begin
            Process.kill("TERM", pid)
          rescue Errno::ESRCH
            nil
          end
          begin
            Process.wait(pid)
          rescue Errno::ECHILD
            nil
          end
        end
        reader.close unless reader.closed?
        writer.close unless writer.closed?
      end
    end

    assert status&.success?, output
    refute_match(/Error|from .+\.rb:\d+/, output)
  end

  # A real terminal, a real model call: proof the ordinary conversational
  # path still answers after a routing change, not just that the process
  # boots. MASTER defaults to Norwegian (CLAUDE.md), so a plain greeting
  # is the cheapest real round trip through chat -> dispatcher -> a live
  # model and back to a clean prompt.
  #
  # A live model is the network and a provider's quota, so this runs under
  # `rake test:cli_e2e` (MASTER_CLI_E2E=1) with the other subprocess tests; in
  # the default suite a provider that is slow or out of credit failed CI.
  def test_plain_chitchat_gets_a_reply_and_returns_to_prompt
    skip "set MASTER_CLI_E2E=1 to drive a live model turn" unless ENV["MASTER_CLI_E2E"] == "1"

    response_token = "MSTR63"
    message = "Reply with exactly #{response_token} and no other words."
    output, status = drive_conversation(message, response_token:)

    assert_equal 0, status.exitstatus, output
    refute_match(/Error|from .+\.rb:\d+/, output)
    assert_match(/MSTR63/, output, "the submitted message never received a model reply")
  end

  private

  def drive_conversation(message, response_token:)
    require "pty"
    output = +""
    PTY.spawn(boot_env, Master::BUNDLE_BIN, "exec", "ruby", "bin/master", chdir: ROOT) do |reader, writer, pid|
      read_until(reader, output, READY, 30)
      sleep 0.5
      start = output.length
      writer.write("#{message}\n")
      read_until_after(reader, output, Regexp.new(Regexp.escape(message)), start:, seconds: 10)
      echo_at = output.index(message, start)
      flunk "CLI did not echo the submitted message: #{output[-1200, 1200]}" unless echo_at
      reply_start = echo_at + message.length
      read_until_after(reader, output, Regexp.new(Regexp.escape(response_token)), start: reply_start, seconds: 90)
      reply_at = output.index(response_token, reply_start)
      flunk "CLI did not answer the submitted message: #{output[-1200, 1200]}" unless reply_at
      reply_end = reply_at + response_token.length
      read_until_after(reader, output, READY, start: reply_end, seconds: 30)
      flunk "CLI did not return to its working prompt after the reply: #{output[-1200, 1200]}" unless output[reply_end..].to_s.match?(READY)
      writer.write("\x04")
      read_until(reader, output, nil, 20)
      _, status = Process.waitpid2(pid)
      return [output, status]
    end
  end

  def read_until_after(reader, output, pattern, start:, seconds:)
    deadline = Time.now + seconds
    while Time.now < deadline
      break if output[start..].to_s.match?(pattern)
      next unless reader.wait_readable(0.2)

      output << reader.readpartial(4096)
    end
  rescue Errno::EIO, EOFError
    output
  end

  def drive
    require "pty"
    output = +""
    PTY.spawn(boot_env, Master::BUNDLE_BIN, "exec", "ruby", "bin/master", chdir: ROOT) do |reader, writer, pid|
      read_until(reader, output, READY, 30)
      sleep 0.5
      yield writer
      read_until(reader, output, nil, 10)
      _, status = Process.waitpid2(pid)
      return [output, status]
    end
  end

  def write_terminal(writer, bytes)
    writer.write(bytes)
  rescue Errno::EIO, Errno::EPIPE
    nil
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
