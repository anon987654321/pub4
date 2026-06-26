# frozen_string_literal: true

require_relative "../test_helper"

class TestVideoChain < Minitest::Test
  class FakeReplicate
    def predict(model_id, input)
      case model_id
      when /flux/
        ["https://example.com/keyframe.png"]
      else
        ["https://example.com/clip.mp4"]
      end
    end
  end

  def setup
    @root = Dir.mktmpdir("video_chain")
    @video_bytes = "fake-mp4-bytes"
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  def test_generate_stitches_chunks_with_analog_post
    ffmpeg_calls = []
    with_video_stubs(ffmpeg_calls: ffmpeg_calls) do
      result = Master::Reach::VideoChain.generate(
        prompt: "neon alley chase",
        backend: :kling,
        total_minutes: 0.35,
        chunk_seconds: 10,
        max_threads: 2,
        root: @root,
        replicate: FakeReplicate.new
      )
      assert File.exist?(result[:path])
      assert_match(/cinematic_kling_/, result[:path])
      assert_operator ffmpeg_calls.size, :>=, 3
    end
  end

  def test_motion_critique_offline_without_agent
    verdict = Master::Judge::Council::MotionCritique.critique("/tmp/fake.mp4", "test prompt", agent: nil)
    assert verdict[:passed]
    assert_operator verdict[:score], :>, 0
  end

  def test_parse_video_args
    parsed = Master::Now::CommandRegistry.parse_video_args(
      "--backend happyhorse --minutes 5 --critique neon rain chase"
    )
    assert_equal :happyhorse, parsed[:backend]
    assert_in_delta 5.0, parsed[:minutes]
    assert parsed[:critique]
    assert_equal "neon rain chase", parsed[:prompt]
  end

  private

  def with_video_stubs(ffmpeg_calls:)
    download = Master::Reach::VideoPost.method(:download_url)
    ffmpeg = Master::Reach::VideoPost.method(:run_ffmpeg)
    Master::Reach::VideoPost.define_singleton_method(:download_url) do |url, path|
      File.binwrite(path, @video_bytes)
      path
    end
    Master::Reach::VideoPost.define_singleton_method(:run_ffmpeg) do |argv|
      ffmpeg_calls << argv
      output = argv.last
      File.binwrite(output, @video_bytes) unless File.exist?(output)
      true
    end
    yield
  ensure
    Master::Reach::VideoPost.define_singleton_method(:download_url, download)
    Master::Reach::VideoPost.define_singleton_method(:run_ffmpeg, ffmpeg)
  end
end