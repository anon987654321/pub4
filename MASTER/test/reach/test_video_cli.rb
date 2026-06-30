# frozen_string_literal: true

require "open3"
require_relative "../test_helper"

class TestVideoCli < Minitest::Test
  def test_help_usage_includes_vision_critique
    usage = Master::Reach::VideoCli.video_usage
    assert_includes usage, "--vision-critique"
    assert_includes usage, "--per-chunk-critique"
    assert_includes usage, "animatediff_camera"
  end

  def test_bin_video_help_exits_zero
    root = File.expand_path("../..", __dir__)
    out, status = Open3.capture2e("bundle", "exec", "ruby", "bin/video", "help", chdir: root)
    assert status.success?, out
    assert_includes out, "motion-dataset"
    assert_includes out, "lora-train"
  end

  def test_parse_lora_train_args
    parsed = Master::Reach::VideoCli.parse_lora_train_args(
      '--name ragnhild --trigger ragnhild --prepare-only --use-all-frames /tmp/a.jpg "/tmp/b roll.mp4"'
    )
    refute parsed[:usage]
    assert_equal "ragnhild", parsed[:name]
    assert_equal "ragnhild", parsed[:trigger_word]
    assert parsed[:prepare_only]
    assert parsed[:split_videos]
    assert parsed[:use_all_frames]
    assert_equal :ranked, parsed[:curation_strategy]
    assert_equal ["/tmp/a.jpg", "/tmp/b roll.mp4"], parsed[:sources]
  end

  def test_parse_lora_train_defaults_trigger_to_name
    parsed = Master::Reach::VideoCli.parse_lora_train_args(
      "--name ragnhild --prepare-only /tmp/a.jpg"
    )
    assert_equal "ragnhild", parsed[:trigger_word]
  end

  def test_parse_lora_train_local_args
    parsed = Master::Reach::VideoCli.parse_lora_train_args(
      "--name ragnhild --local --ai-toolkit /opt/ai-toolkit --steps 1000 --rank 64 --lr 7e-5 --caption-dropout 0.08 /tmp/a.jpg"
    )
    refute parsed[:usage]
    assert parsed[:local]
    assert_equal "/opt/ai-toolkit", parsed[:ai_toolkit_root]
    assert_equal 1000, parsed[:steps]
    assert_equal 64, parsed[:rank]
    assert_equal "7e-5", parsed[:learning_rate]
    assert_equal "v2", parsed[:version]
    assert_in_delta 0.08, parsed[:caption_dropout_rate]
  end

  def test_parse_lora_train_curation_args
    parsed = Master::Reach::VideoCli.parse_lora_train_args(
      "--name ragnhild --curation even --max-images 60 --max-per-source 35 --min-frame-gap 8 /tmp/a.mp4"
    )
    assert_equal :even, parsed[:curation_strategy]
    assert_equal 60, parsed[:max_images]
    assert_equal 35, parsed[:max_per_source]
    assert_equal 8, parsed[:min_frame_gap]
  end
end
