# frozen_string_literal: true

require_relative "tools_helper"
ToolTest::Tools.load_tool("postpro/postpro.rb")
require "stringio"
require "digest"
require "open3"
require "tmpdir"
require_relative "../postpro/motion"

class TestPostproMotion < Minitest::Test
  def test_fractional_frame_rates_are_parsed_without_integer_truncation
    assert_in_delta 23.976, Postpro::Motion.parse_fps("24000/1001"), 0.001
    assert_in_delta 25.0, Postpro::Motion.parse_fps("25/1"), 0.001
    assert_in_delta 30.0, Postpro::Motion.parse_fps("30"), 0.001
  end

  def test_grain_modes_are_deterministic_and_distinct
    assert_equal [100, 101, 102, 103], (0..3).map { |i| Postpro::Motion.seed_for(i, 100) }
    assert_equal [100, 100, 100, 100], (0..3).map { |i| Postpro::Motion.seed_for(i, 100, grain: :hold) }
    refute_equal Postpro::Motion.seed_for(1, 100), Postpro::Motion.seed_for(1, 100, grain: :hold)
    assert_raises(ArgumentError) { Postpro::Motion.seed_for(0, 100, grain: :guess) }
  end

  def clip(directory, name: "clip.mp4", audio: true)
    skip "ffmpeg/ffprobe not on PATH — nothing was measured" unless Postpro::Motion.available?
    path = File.join(directory, name)
    command = [
      "ffmpeg", "-nostdin", "-v", "error", "-y",
      "-f", "lavfi", "-i", "testsrc2=size=96x64:rate=4:duration=1"
    ]
    command.concat(["-f", "lavfi", "-i", "sine=frequency=440:duration=1"]) if audio
    command.concat(["-c:v", "libx264", "-pix_fmt", "yuv420p"])
    command.concat(["-c:a", "aac", "-shortest"]) if audio
    command << path
    _output, status = Open3.capture2e(*command)
    assert status.success?, "could not build the fixture clip"
    path
  end

  def grade(source, target, seed: 42, grain: :moving)
    Postpro::Motion.grade(
      source, target, preset: :portrait, seed:, grain:, io: StringIO.new
    ) do |bytes, width, height, output, frame_seed|
      postpro_video_grade_frame(bytes, width, height, output, :portrait, frame_seed)
    end
  end

  def test_probe_reads_actual_dimensions_frame_rate_and_audio
    Dir.mktmpdir do |directory|
      probe = Postpro::Motion.probe(clip(directory))

      assert_equal 96, probe.width
      assert_equal 64, probe.height
      assert_in_delta 4.0, probe.fps, 0.01
      assert_equal 4, probe.frames
      assert probe.has_audio
    end
  end


  def test_a_file_without_video_stream_is_refused
    skip "ffmpeg/ffprobe not on PATH — nothing was measured" unless Postpro::Motion.available?

    Dir.mktmpdir do |directory|
      audio_only = File.join(directory, "tone.m4a")
      _output, status = Open3.capture2e(
        "ffmpeg", "-nostdin", "-v", "error", "-y", "-f", "lavfi",
        "-i", "sine=frequency=440:duration=1", audio_only
      )
      assert status.success?, "could not build the audio-only fixture"

      error = assert_raises(Postpro::Motion::Unavailable) do
        Postpro::Motion.probe(audio_only)
      end
      assert_match(/no video stream/, error.message)
    end
  end

  def test_frame_budget_refuses_work_before_invoking_the_grader
    skip "ffmpeg/ffprobe not on PATH — nothing was measured" unless Postpro::Motion.available?

    Dir.mktmpdir do |directory|
      source = clip(directory, audio: false)
      target = File.join(directory, "over-budget.mp4")
      previous = ENV["POSTPRO_VIDEO_MAX_FRAMES"]
      ENV["POSTPRO_VIDEO_MAX_FRAMES"] = "2"
      begin
        error = assert_raises(Postpro::Motion::Unavailable) do
          Postpro::Motion.grade(source, target, preset: :portrait, io: StringIO.new) do
            flunk "the frame-grading callback must not run after preflight rejects the clip"
          end
        end
        assert_match(/exceeds the 2-frame budget/, error.message)
        refute File.exist?(target)
        refute File.exist?("#{target}.json")
      ensure
        previous ? ENV["POSTPRO_VIDEO_MAX_FRAMES"] = previous : ENV.delete("POSTPRO_VIDEO_MAX_FRAMES")
      end
    end
  end

  def test_a_video_grade_keeps_dimensions_and_audio
    Dir.mktmpdir do |directory|
      source = clip(directory)
      target = File.join(directory, "graded.mp4")
      grade(source, target)

      probe = Postpro::Motion.probe(target)
      assert_equal [96, 64], [probe.width, probe.height]
      assert probe.has_audio
      assert_equal 4, probe.frames
      sidecar = JSON.parse(File.read("#{target}.json"))
      assert_equal 42, sidecar.dig("grade", "seed")
      assert_equal GRADE_VERSION, sidecar.fetch("grade_version")
      assert_equal "moving", sidecar.dig("grade", "grain")
      assert_equal 4, sidecar.dig("video", "frame_count")
      assert_equal Digest::SHA256.file(target).hexdigest, sidecar.dig("output", "sha256")
    end
  end

  def test_same_seed_reproduces_the_same_clip_and_held_grain_is_a_real_choice
    Dir.mktmpdir do |directory|
      source = clip(directory, audio: false)
      first = File.join(directory, "first.mp4")
      second = File.join(directory, "second.mp4")
      held = File.join(directory, "held.mp4")

      grade(source, first, seed: 7)
      grade(source, second, seed: 7)
      grade(source, held, seed: 7, grain: :hold)

      first_hash = Digest::SHA256.file(first).hexdigest
      assert_equal first_hash, Digest::SHA256.file(second).hexdigest
      refute_equal first_hash, Digest::SHA256.file(held).hexdigest
    end
  end

  def test_existing_video_is_never_clobbered
    Dir.mktmpdir do |directory|
      source = clip(directory, audio: false)
      target = File.join(directory, "keep.mp4")
      File.write(target, "earlier output")

      error = assert_raises(Postpro::Motion::Unavailable) do
        grade(source, target)
      end
      assert_match(/refusing to replace an existing video/, error.message)
      assert_equal "earlier output", File.read(target)
    end
  end

  def test_a_failed_grade_publishes_neither_video_nor_sidecar
    Dir.mktmpdir do |directory|
      source = clip(directory, audio: false)
      target = File.join(directory, "failed.mp4")

      error = assert_raises(Postpro::Motion::Unavailable) do
        Postpro::Motion.grade(source, target, preset: :portrait, io: StringIO.new) do
          raise "synthetic failure"
        end
      end
      assert_match(/grading frame/, error.message)
      refute File.exist?(target)
      refute File.exist?("#{target}.json")
    end
  end
end
