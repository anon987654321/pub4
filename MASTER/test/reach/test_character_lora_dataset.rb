# frozen_string_literal: true

require "fileutils"
require_relative "../test_helper"

class TestCharacterLoraDataset < Minitest::Test
  def setup
    @root = File.join(Dir.tmpdir, "char_lora_ds_#{Process.pid}")
    @sources_dir = File.join(@root, "sources")
    FileUtils.mkdir_p(@sources_dir)
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  def test_prepare_collects_stills
    still = File.join(@sources_dir, "selfie.jpg")
    File.write(still, "x" * 30_000)
    subject_root = Master::Reach::CharacterLoraDataset.training_dir("test_subject", root: @root)
    FileUtils.mkdir_p(File.dirname(subject_root))
    stub_deploy = Module.new do
      define_singleton_method(:deploy_path) { |*parts| File.join(@root, "repligen", *parts) }
    end
    Master.stub(:deploy_path, ->(*parts) { File.join(@root, "repligen", *parts) }) do
      result = Master::Reach::CharacterLoraDataset.prepare(
        name: "test_subject",
        sources: [still],
        root: @root
      )
      assert_equal 1, result[:count]
      assert File.directory?(result[:dir])
      assert File.exist?(File.join(result[:out_dir], "meta.json"))
      assert File.exist?(File.join(result[:dir], "a_photo_of_test_subject_01.txt"))
    end
  end

  def test_curate_evenly_samples_down_to_max
    images = (1..30).map { |index| "img_#{index}.jpg" }
    curated = Master::Reach::CharacterLoraDataset.curate_images(images, min_images: 12, max_images: 18, strategy: :even)
    assert_equal 18, curated.size
  end

  def test_ranked_curation_prefers_larger_files
    small = File.join(@sources_dir, "small.jpg")
    large = File.join(@sources_dir, "large.jpg")
    File.write(small, "x" * 25_000)
    File.write(large, "x" * 200_000)
    curated = Master::Reach::CharacterLoraDataset.curate_images([small, large], min_images: 1, max_images: 1, strategy: :ranked)
    assert_equal [large], curated
  end

  def test_min_frame_gap_filters_dense_sequences
    frames = (1..10).map { |index| File.join(@sources_dir, format("frame_%06d.jpg", index)) }
    filtered = Master::Reach::CharacterLoraDataset.apply_min_frame_gap(frames, 4)
    assert_equal [
      File.join(@sources_dir, "frame_000001.jpg"),
      File.join(@sources_dir, "frame_000005.jpg"),
      File.join(@sources_dir, "frame_000009.jpg"),
    ], filtered
  end
end
