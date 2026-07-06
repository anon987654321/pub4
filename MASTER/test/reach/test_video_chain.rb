# frozen_string_literal: true

require "json"
require_relative "../test_helper"

class TestVideoChain < Minitest::Test
  class FakeReplicate
    def predict(model_id, _input)
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
    @ffmpeg_calls = []
    @download_stub = lambda do |_url, path|
      File.binwrite(path, @video_bytes)
      path
    end
    calls = @ffmpeg_calls
    bytes = @video_bytes
    @ffmpeg_stub = lambda do |argv|
      calls << argv
      output = argv.last
      File.binwrite(output, bytes) unless File.exist?(output)
      true
    end
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  def test_generate_stitches_chunks_with_analog_post
    with_video_stubs do
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
      assert File.exist?(result[:manifest])
      assert_operator @ffmpeg_calls.size, :>=, 3
    end
  end

  def test_generate_commercial_exact_seconds_with_grade_manifest
    with_video_stubs do
      result = Master::Reach::VideoChain.generate(
        prompt: "premium skincare launch",
        backend: :kling,
        total_seconds: 36,
        chunk_seconds: 8,
        video_format: :commercial,
        grade_preset: "commercial",
        aspect_ratio: "16:9",
        max_threads: 1,
        root: @root,
        replicate: FakeReplicate.new
      )
      assert File.exist?(result[:path])
      assert_match(/commercial_grade\.mp4\z/, result[:path])
      manifest = JSON.parse(File.read(result[:manifest]))
      assert_equal 36, manifest["seconds"]
      assert_equal "commercial", manifest["format"]
      assert_equal 5, manifest["scene_prompts"].size
      assert manifest["scene_prompts"].first.include?("opening hook")
      grade_call = @ffmpeg_calls.find { |argv| argv.include?("-t") && argv.include?("36.0") }
      assert grade_call, "expected final grade to trim to exact duration"
    end
  end

  def test_direct_response_prompt_uses_camera_continuity_and_cta_metadata
    with_video_stubs do
      result = Master::Reach::VideoChain.generate(
        prompt: "premium launch film",
        backend: :kling,
        total_seconds: 32,
        chunk_seconds: 8,
        video_format: :direct_response,
        camera_plan: :product,
        continuity: :strict,
        offer: "early access bundle",
        cta_label: "reserve now",
        cta_url: "https://example.com/offer",
        max_threads: 1,
        root: @root,
        replicate: FakeReplicate.new
      )
      manifest = JSON.parse(File.read(result[:manifest]))
      assert_equal "direct_response", manifest["format"]
      assert_equal "product", manifest["camera_plan"]
      assert_equal "strict", manifest["continuity"]
      assert_equal "early access bundle", manifest["offer"]
      assert_equal "reserve now", manifest["cta_label"]
      assert_equal "https://example.com/offer", manifest["cta_url"]
      first_prompt = manifest["scene_prompts"].first
      assert first_prompt.include?("macro slide") || first_prompt.include?("hero packshot")
      assert manifest["scene_prompts"].last.include?("call-to-action intent")
      assert manifest["scene_prompts"].last.include?("leave clean negative space")
    end
  end

  def test_motion_critique_offline_without_agent
    verdict = Master::Judge::Council::MotionCritique.critique("/tmp/fake.mp4", "test prompt", agent: nil)
    assert verdict[:passed]
    assert_operator verdict[:score], :>, 0
  end

  def test_parse_video_args
    parsed = Master::Reach::VideoCli.parse_video_args(
      "--backend happyhorse --minutes 5 --critique --vision-critique --auto-retry neon rain chase"
    )
    assert_equal :happyhorse, parsed[:backend]
    assert_in_delta 5.0, parsed[:minutes]
    assert parsed[:critique]
    assert parsed[:vision_critique]
    assert parsed[:auto_retry_weak]
    assert_equal "neon rain chase", parsed[:prompt]
  end

  def test_motion_preset_splits_stacked_loras
    opts = {
      motion_lora: "primary.safetensors,secondary.safetensors",
      motion_lora_weight: 0.8,
      motion_lora_2: nil,
      motion_lora_2_weight: nil,
      camera_phrase: nil,
      motion_preset: nil,
      motion_loras: [],
    }
    chain = Master::Reach::VideoChain.allocate
    chain.send(:split_stacked_motion_loras!, opts)
    assert_equal "primary.safetensors", opts[:motion_lora]
    assert_equal "secondary.safetensors", opts[:motion_lora_2]
  end

  def test_motion_lora_presets_resolve
    resolved = Master::Reach::MotionLoraPresets.resolve("slow_dolly_push_in")
    assert resolved
    assert_match(/safetensors\z/, resolved[:motion_lora])
  end

  def test_chunk_indices_from_flagged_supports_scene_numbers
    chain = Master::Reach::VideoChain.allocate
    assert_equal [0, 2], chain.send(:chunk_indices_from_flagged, [1, 3], 5)
    assert_equal [0, 2], chain.send(:chunk_indices_from_flagged, [0, 2], 5)
  end

  def test_per_chunk_critique_defaults_with_auto_retry
    opts = { auto_retry_weak: true, per_chunk_critique: nil }
    chain = Master::Reach::VideoChain.allocate
    assert chain.send(:per_chunk_critique_default, opts)
  end

  def test_auto_retry_regenerates_flagged_chunks
    calls = 0
    critique_stub = lambda do |_path, _prompt, **|
      calls += 1
      if calls == 1
        { score: 6.0, overall_score: 6.0, flagged_chunks: [1], weak_chunks: [1], passed: false, mode: :offline }
      else
        { score: 9.0, overall_score: 9.0, flagged_chunks: [], weak_chunks: [], passed: true, mode: :offline }
      end
    end

    with_video_stubs do
      chain = Master::Reach::VideoChain.new(
        root: @root,
        replicate: FakeReplicate.new
      )
      chain.stub(:run_critique, critique_stub) do
        result = chain.generate(
          prompt: "retry test",
          backend: :kling,
          total_minutes: 0.35,
          chunk_seconds: 10,
          max_threads: 1,
          auto_retry_weak: true,
          max_weak_retries: 1,
          critique: true
        )
        assert_match(/retry1/, result[:path])
        assert_equal 1, result[:regenerated].size
        assert_equal 0, result[:regenerated].first[:chunk]
      end
    end
  end

  private

  def with_video_stubs
    download = Master::Reach::VideoPost.method(:download_url)
    ffmpeg = Master::Reach::VideoPost.method(:run_ffmpeg)
    Master::Reach::VideoPost.define_singleton_method(:download_url, &@download_stub)
    Master::Reach::VideoPost.define_singleton_method(:run_ffmpeg, &@ffmpeg_stub)
    yield
  ensure
    Master::Reach::VideoPost.define_singleton_method(:download_url, download)
    Master::Reach::VideoPost.define_singleton_method(:run_ffmpeg, ffmpeg)
  end
end
