# frozen_string_literal: true

require "minitest/autorun"
require "fileutils"
require "tmpdir"
require_relative "../dilla/lib/ffmpeg_probe"
require_relative "../dilla/lib/mix_score"

# The scoring modules read ffmpeg through backticks and `.to_f`, so a path with
# a quote in it was a shell command and a file ffmpeg could not open scored
# 0.0 dB. These pin the replacement: argument vectors, and failure as failure.
class TestFfmpegProbe < Minitest::Test
  def setup
    skip "ffmpeg not installed" unless system("ffmpeg", "-version", out: File::NULL, err: File::NULL)
    @dir = Dir.mktmpdir("probe")
  end

  def teardown
    FileUtils.rm_rf(@dir) if @dir
  end

  def sine(name)
    path = File.join(@dir, name)
    ok = system("ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i", "sine=frequency=440:duration=1",
                path, out: File::NULL, err: File::NULL)
    assert ok, "could not make the fixture"
    path
  end

  def test_a_quoted_path_is_measured_not_executed
    path = sine(%(it's "a" take.wav))
    level = MixScore.band(path, 200, 2000)

    assert_operator level, :<, 0.0
    assert_operator level, :>, -40.0, "a 440 Hz sine should sit inside a 200-2000 Hz band"
  end

  def test_a_missing_file_raises_instead_of_scoring_zero
    assert_raises(FfmpegProbe::Error) { MixScore.loudness(File.join(@dir, "nope.wav")) }
  end

  def test_a_log_without_the_reading_raises
    assert_raises(FfmpegProbe::Error) { FfmpegProbe.number("no readings here", /mean_volume: ([-0-9.]+)/, what: "mean") }
  end
end
