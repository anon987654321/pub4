# frozen_string_literal: true

require "minitest/autorun"
require "fileutils"
require "tmpdir"
require_relative "../dilla/lib/listen"

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
# A quiet opening is the case the running frame lines get wrong: the first I
# ebur128 prints is the file's opening instant. The summary is the reading.
def test_the_loudness_reading_is_the_summary_not_the_first_frame
  path = File.join(@dir, "quiet head.wav")
  ok = system("ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i", "sine=f=220:d=12,volume=enable=lt(t\\,3):volume=0.001",
              "-ac", "2", path, out: File::NULL, err: File::NULL)
  assert ok, "could not make the fixture"
  reading = FfmpegProbe.ebur128_summary(FfmpegProbe.run(path, "ebur128=peak=true"))

  assert_operator reading[:i], :>, -40.0, "read the opening frame instead of the summary"
  assert_operator reading[:tp], :<, 0.0
end

def test_duration_is_measured_and_a_missing_file_raises
  assert_in_delta 1.0, FfmpegProbe.duration(sine("one second.wav")), 0.05
  assert_raises(FfmpegProbe::Error) { FfmpegProbe.duration(File.join(@dir, "nope.wav")) }
end

def test_loudnorm_and_volumedetect_logs_parse_and_absence_is_nil
  assert_equal(-23.4, FfmpegProbe.loudnorm_json(%({\n "input_i" : "-23.4",\n "input_tp" : "-1.0"\n}))["input_i"].to_f)
  assert_empty FfmpegProbe.loudnorm_json("nothing")
  assert_equal({ mean: -20.5, max: -3.0 }, FfmpegProbe.volumedetect("mean_volume: -20.5 dB\nmax_volume: -3.0 dB"))
  assert_nil FfmpegProbe.volumedetect("nothing")[:mean]
end
end
