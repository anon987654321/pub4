# frozen_string_literal: true

require "minitest/autorun"
require "timeout"
require "tmpdir"
require "rbconfig"
require_relative "../dilla/lib/listen"

# ToolRun is how dilla runs a tool that is not a render step. It must keep the
# contract of the call it replaced -- Open3's return values, Kernel#system's
# true, false and nil -- and add a deadline that actually ends the run, which
# means killing whatever the tool started too.
class TestDillaToolRun < Minitest::Test
  # A test that hangs is the failure these guard against, so each one is held to
  # a deadline of its own.
  def within(seconds, &block) = Timeout.timeout(seconds, &block)

  def test_capture3_returns_what_open3_returns
    output, error, status = within(10) { ToolRun.capture3("sh", "-c", "printf out; printf err >&2") }

    assert_equal ["out", "err"], [output, error]
    assert_predicate status, :success?
  end

  # The background sleep holds the output pipe open. Killing only the shell
  # would leave the readers waiting on it for thirty seconds.
  def test_a_run_past_its_deadline_ends_with_everything_it_started
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    _output, error, status = within(10) { ToolRun.capture3("sh", "-c", "sleep 30 & sleep 30", timeout: 0.5) }

    refute_predicate status, :success?
    assert_includes error, "timeout after 0.5s"
    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 5
  end

  # Input is written and the pipe closed, or a tool reading to the end of its
  # input never finishes; a tool that stops reading early is not an error.
  def test_input_is_fed_and_closed
    output, status = within(10) { ToolRun.capture2e("cat", stdin_data: "abc") }
    assert_equal "abc", output
    assert_predicate status, :success?

    output, = within(10) { ToolRun.capture2e("head", "-c", "1", stdin_data: "x" * 1_000_000) }
    assert_equal "x", output
  end

  def test_binary_output_stays_binary
    output, = within(10) { ToolRun.capture2("printf", "\\377\\376", binmode: true) }

    assert_equal Encoding::BINARY, output.encoding
    assert_equal [255, 254], output.bytes
  end

  def test_system_answers_as_kernel_system_does
    assert_equal true, within(10) { ToolRun.system("true") }
    assert_equal 0, $?.exitstatus
    assert_equal false, within(10) { ToolRun.system("false") }
    assert_nil within(10) { ToolRun.system("no-such-tool-anywhere") }
    assert_equal false, within(10) { ToolRun.system("sleep", "30", timeout: 0.5) }
  end

  # Ctrl-C at a terminal is SIGINT to the engine's foreground group, and a
  # render tool leads a group of its own, so the signal never reaches it. Each
  # of these runs an engine as a group leader, signals it the way a terminal or
  # a `kill` would, and requires the tool it was waiting on to be gone after.
  LISTEN = File.expand_path("../dilla/lib/listen.rb", __dir__)
  ENGINE = File.expand_path("../dilla/dilla.rb", __dir__)
  # A test runner started in the background inherits SIGINT ignored, and Ruby
  # leaves an ignored signal ignored, so the engine asks for its handler back.
  PREAMBLE = %(trap("INT", "DEFAULT"); pidfile = ARGV.fetch(0)\n)
  TOOL = %(["sh", "-c", "echo $$ > \#{pidfile}; exec sleep 300"])
  ENGINE_ENV = { "DILLA_QUIET" => "1", "DILLA_ASSET_CHECK" => "0", "DILLA_KNOB_CHECK" => "0" }.freeze

  def test_ctrl_c_during_tool_run_capture_stops_the_tool
    assert_tool_stopped(%(require #{LISTEN.dump}; ToolRun.capture3(*#{TOOL})), signal: "INT")
  end

  def test_sigterm_during_tool_run_system_stops_the_tool
    assert_tool_stopped(%(require #{LISTEN.dump}; ToolRun.system(*#{TOOL})), signal: "TERM", to_group: false)
  end

  def test_ctrl_c_during_a_render_step_stops_the_tool
    assert_tool_stopped(%(require #{ENGINE.dump}; sh!(*#{TOOL})), signal: "INT")
  end

  # A player shares the engine's group, so only a signal sent to the engine
  # alone can leave one behind.
  def test_sigterm_during_playback_stops_the_player
    Dir.mktmpdir do |bin|
      File.write(File.join(bin, "afplay"), %(#!/bin/sh\necho $$ > "$PLAYER_PIDFILE"\nexec sleep 300\n))
      File.chmod(0o755, File.join(bin, "afplay"))
      env = { "PATH" => "#{bin}:#{ENV['PATH']}" }
      script = %(ENV["PLAYER_PIDFILE"] = pidfile; require #{ENGINE.dump}; sh!("afplay", "take.wav"))
      assert_tool_stopped(script, signal: "TERM", to_group: false, env:)
    end
  end

  # The looped player is stopped with Ctrl-C, so SIGINT to the engine alone has
  # to take the player with it. PATH holds the stand-in player and /bin only:
  # play_audio clears other players with pkill and raises the Mac's volume with
  # osascript, and neither may reach a real speaker from a test.
  def test_ctrl_c_during_a_looped_play_stops_the_player
    Dir.mktmpdir do |bin|
      File.write(File.join(bin, "afplay"), %(#!/bin/sh\necho $$ > "$PLAYER_PIDFILE"\nexec sleep 300\n))
      File.chmod(0o755, File.join(bin, "afplay"))
      take = File.join(bin, "take.wav")
      File.write(take, "RIFF")
      env = { "PATH" => "#{bin}:/bin", "SKIP_VOLUME_NUDGE" => "1" }
      script = %(ENV["PLAYER_PIDFILE"] = pidfile; require #{ENGINE.dump}; play_audio(#{take.dump}, loop: true))
      assert_tool_stopped(script, signal: "INT", to_group: false, env:)
    end
  end

  # Every ffmpeg and ffprobe the engine starts goes through sh! (render steps,
  # with dmesg) or ToolRun (everything else), so every one has a deadline. The
  # exceptions are streams, which last as long as the Ruby feeding them: the
  # live player and the sine stream feed a speaker, and write_stereo_chunks
  # hands ffmpeg a bus four seconds at a time as the synth computes it.
  UNBOUNDED_FILES = %w[lib/livesets.rb lib/sine_stream.rb].freeze
  STREAMS = %w[write_stereo_chunks].freeze
  BYPASS = /(?:Open3\.\w+|IO\.popen|(?<![.\w])system)\(\s*\[?\s*"(?:ffmpeg|ffprobe)"/

  def test_no_ffmpeg_call_bypasses_the_runners
    dilla = File.expand_path("../dilla", __dir__)
    files = ["dilla.rb"] + Dir.children(File.join(dilla, "lib")).map { |name| "lib/#{name}" } - UNBOUNDED_FILES
    bypasses = files.flat_map do |file|
      source = File.read(File.join(dilla, file))
      source.enum_for(:scan, BYPASS).map { Regexp.last_match.begin(0) }.filter_map do |at|
        method = source[0, at].scan(/^\s*def (\w+[!?]?)/).flatten.last
        "#{file}: #{method}" unless STREAMS.include?(method)
      end
    end

    assert_empty bypasses
  end

  private

  def assert_tool_stopped(body, signal:, to_group: true, env: {})
    Dir.mktmpdir do |dir|
      pidfile = File.join(dir, "tool.pid")
      engine = Process.spawn(ENGINE_ENV.merge(env), RbConfig.ruby, "-e", PREAMBLE + body, pidfile,
                             pgroup: true, out: File::NULL, err: File::NULL)
      within(120) { sleep 0.05 until File.size?(pidfile) }
      tool = Integer(File.read(pidfile))
      Process.kill(signal, to_group ? -engine : engine)
      within(30) { Process.wait(engine) }
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 10
      sleep 0.05 while alive?(tool) && Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
      refute alive?(tool), "the tool (pid #{tool}) outlived the engine that was signalled with SIG#{signal}"
    ensure
      stray(tool) if tool
    end
  end

  def alive?(pid)
    Process.kill(0, pid)
    true
  rescue Errno::ESRCH
    false
  end

  def stray(pid)
    Process.kill("KILL", pid)
  rescue Errno::ESRCH
    nil
  end
end
