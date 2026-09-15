# frozen_string_literal: true

require "minitest/autorun"
require "timeout"
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
end
