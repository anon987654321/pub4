# frozen_string_literal: true

require_relative "test_helper"
require "fileutils"
require "tmpdir"

# Melody plans a rest between phrases, and the rest used to be spent as
# `sleep(pause_ms / 1000.0)` inside the synthesis loop — latency in the Ruby
# process, nothing in the audio. concat_mp3 then joined the phrases back to
# back, so every planned rest was inaudible. These pin that the rest reaches the
# file.
class TestMelodicConcat < Minitest::Test
  E = Master::Voice::Engines

  def setup
    skip "ffmpeg/ffprobe not on PATH" unless E.send(:ffmpeg?) && system("which", "ffprobe", out: File::NULL, err: File::NULL)
    @dir = Dir.mktmpdir("melodic-concat")
  end

  def teardown
    FileUtils.remove_entry(@dir) if @dir && File.directory?(@dir)
  end

  # Stands in for an Edge phrase: same container and layout, known duration.
  def tone(name, seconds)
    path = File.join(@dir, name)
    system("ffmpeg", "-y", "-f", "lavfi", "-i", "sine=frequency=440:r=24000",
           "-ac", "1", "-t", format("%.3f", seconds), "-b:a", "48000", path,
           out: File::NULL, err: File::NULL)
    path
  end

  def duration(path)
    out, _err, status = Master::Io::Exec.capture3(
      "ffprobe", "-v", "error", "-show_entries", "format=duration",
      "-of", "default=noprint_wrappers=1:nokey=1", path
    )
    status.success? ? out.to_s.strip.to_f : nil
  end

  def test_planned_rests_are_audible_in_the_concatenated_output
    parts = [[tone("a.mp3", 0.5), 0], [tone("b.mp3", 0.5), 300]]
    out = File.join(@dir, "out.mp3")

    assert E.send(:concat_mp3, parts, out, @dir)
    # 0.5 + 0.3 + 0.5. mp3 frame granularity is ~26ms per part, so allow slack.
    assert_in_delta 1.3, duration(out), 0.12
  end

  def test_no_rest_means_no_added_silence
    parts = [[tone("a.mp3", 0.5), 0], [tone("b.mp3", 0.5), 0]]
    out = File.join(@dir, "out.mp3")

    assert E.send(:concat_mp3, parts, out, @dir)
    assert_in_delta 1.0, duration(out), 0.12
  end

  # -c copy joins mp3s without complaint even when they disagree on sample rate
  # or channel count, and the result plays back at the wrong speed from the join
  # onward. The silence is probed from the speech rather than assumed.
  def test_silence_matches_the_format_it_is_spliced_into
    part = tone("a.mp3", 0.4)
    fmt = E.send(:silence_format, part)

    assert_equal 24_000, fmt[:rate]
    assert_equal 1, fmt[:channels]

    rest = E.send(:silence_part, 200, fmt, @dir, 0)
    assert rest, "silence part was not generated"
    assert_equal fmt[:rate], E.send(:silence_format, rest)[:rate]
    assert_equal fmt[:channels], E.send(:silence_format, rest)[:channels]
  end

  def test_rests_are_interleaved_before_the_phrase_they_precede
    a = tone("a.mp3", 0.3)
    b = tone("b.mp3", 0.3)

    sequence = E.send(:concat_sequence, [[a, 0], [b, 140]], @dir)

    assert_equal 3, sequence.length
    assert_equal a, sequence[0]
    assert_equal b, sequence[2]
    assert_match(/rest_/, sequence[1])
  end
end
