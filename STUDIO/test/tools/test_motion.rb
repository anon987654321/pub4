# frozen_string_literal: true

require_relative "../helper"
require "tmpdir"
require "digest"
require "stringio"
require "open3"
require_relative "../../postpro/motion"

# postpro on video. The grade is the same code that runs on stills — that is
# the design, not an implementation detail, because a video graded one way and
# a photograph graded another are two looks and this tree only wants one.
#
# Everything here needs ffmpeg. Where it is absent the tests say so and skip
# rather than passing, because a green run on a machine that measured nothing
# is the failure this whole tree keeps finding.
class TestMotion < Minitest::Test
  def setup
    skip "ffmpeg/ffprobe not on PATH — nothing was measured" unless Postpro::Motion.available?
  end

  # Two seconds at 12fps: 24 frames, small enough to grade inside a test and
  # long enough that the temporal questions are real.
  def clip(dir, name: "clip.mp4", audio: true)
    path = File.join(dir, name)
    args = ["ffmpeg", "-nostdin", "-v", "error", "-y",
            "-f", "lavfi", "-i", "testsrc2=size=160x120:rate=12:duration=2"]
    args += ["-f", "lavfi", "-i", "sine=frequency=440:duration=2"] if audio
    args += ["-c:v", "libx264", "-pix_fmt", "yuv420p"]
    args += ["-c:a", "aac", "-shortest"] if audio
    args << path
    _out, status = Open3.capture2e(*args)
    assert status.success?, "could not build the fixture clip"
    path
  end

  def test_probe_reads_the_stream_rather_than_the_extension
    Dir.mktmpdir do |dir|
      probe = Postpro::Motion.probe(clip(dir))

      assert_equal 160, probe.width
      assert_equal 120, probe.height
      assert_in_delta 12.0, probe.fps, 0.01
      assert probe.has_audio, "the fixture has an audio track and probe has to see it"
    end
  end

  # 24000/1001 is 23.976. Reading it as an integer loses the pulldown that
  # every telecined source carries, and 24 vs 23.976 drifts a second an hour.
  def test_fractional_frame_rates_survive
    assert_in_delta 23.976, Postpro::Motion.parse_fps("24000/1001"), 0.001
    assert_in_delta 25.0, Postpro::Motion.parse_fps("25/1"), 0.001
    assert_in_delta 30.0, Postpro::Motion.parse_fps("30"), 0.001
  end

  def test_a_file_with_no_video_stream_says_so
    Dir.mktmpdir do |dir|
      audio_only = File.join(dir, "tone.m4a")
      Open3.capture2e("ffmpeg", "-nostdin", "-v", "error", "-y", "-f", "lavfi",
                      "-i", "sine=frequency=440:duration=1", audio_only)

      assert_raises(Postpro::Motion::Unavailable) { Postpro::Motion.probe(audio_only) }
    end
  end

  # The temporal problem, which is the whole difficulty. Grain re-randomised per
  # frame boils, and that is the classic tell of a stills filter applied to
  # video by someone who was not thinking about time.
  def test_moving_grain_advances_and_held_grain_does_not
    assert_equal [100, 101, 102, 103], (0..3).map { |i| Postpro::Motion.seed_for(i, 100) }
    assert_equal [100, 100, 100, 100],
                 (0..3).map { |i| Postpro::Motion.seed_for(i, 100, grain: :hold) }
  end

  def test_a_graded_clip_keeps_its_dimensions_and_its_audio
    Dir.mktmpdir do |dir|
      source = clip(dir)
      output = File.join(dir, "graded.mp4")
      Postpro::Motion.grade(source, output, preset: "portrait", seed: 42, io: StringIO.new)

      after = Postpro::Motion.probe(output)

      assert_equal 160, after.width
      assert_equal 120, after.height
      assert after.has_audio, "the audio track has to survive the grade"
    end
  end

  # Without this nothing about a clip can be compared to anything, including a
  # later version of itself.
  def test_the_same_seed_produces_the_same_clip
    Dir.mktmpdir do |dir|
      source = clip(dir, audio: false)
      first = File.join(dir, "a.mp4")
      second = File.join(dir, "b.mp4")
      Postpro::Motion.grade(source, first, preset: "portrait", seed: 7, io: StringIO.new)
      Postpro::Motion.grade(source, second, preset: "portrait", seed: 7, io: StringIO.new)

      assert_equal Digest::SHA256.file(first).hexdigest, Digest::SHA256.file(second).hexdigest,
                   "a seeded grade has to be reproducible or nothing downstream can be measured"
    end
  end

  def test_held_grain_and_moving_grain_are_different_pictures
    Dir.mktmpdir do |dir|
      source = clip(dir, audio: false)
      moving = File.join(dir, "moving.mp4")
      held = File.join(dir, "held.mp4")
      Postpro::Motion.grade(source, moving, preset: "portrait", seed: 7, io: StringIO.new)
      Postpro::Motion.grade(source, held, preset: "portrait", seed: 7, grain: :hold, io: StringIO.new)

      refute_equal Digest::SHA256.file(moving).hexdigest, Digest::SHA256.file(held).hexdigest,
                   "if these match, the grain mode is not reaching the grade and the choice is decorative"
    end
  end

  def test_the_estimate_is_given_before_the_work_rather_than_after
    Dir.mktmpdir do |dir|
      estimate = Postpro::Motion.estimate(Postpro::Motion.probe(clip(dir)))

      assert_operator estimate[:frames], :>, 0
      assert_operator estimate[:seconds], :>, 0
    end
  end
end
