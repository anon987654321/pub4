# frozen_string_literal: true

require "minitest/autorun"
require_relative "../replicate/lora/merethe/prepare"

class TestMeretheLoraPackage < Minitest::Test
  def test_historical_source_inventory_is_complete_and_pinned
    assert_equal 15, Studio::MeretheLora::SOURCE_FILES.size
    assert_equal "8e1955ae130592ab7c20ee266c024f061431c67e", Studio::MeretheLora::SOURCE_COMMIT
    assert Studio::MeretheLora::SOURCE_FILES.values.all? { |sha| sha.match?(/\A[0-9a-f]{40}\z/) }
  end

  def test_only_face_led_candidates_enter_the_initial_identity_set
    assert_equal %w[10.jpg 11.jpg 12.jpg 13.jpg], Studio::MeretheLora::CURATED_CAPTIONS.keys
    assert Studio::MeretheLora::CURATED_CAPTIONS.values.all? { |caption| caption.include?("MERETHE") }
  end

  def test_preflight_minimum_matches_trainer_floor_and_target_range
    assert_equal 10, Studio::MeretheLora::MIN_IMAGES
    assert_equal [12, 18], [Studio::MeretheLora::TARGET_MIN_IMAGES, Studio::MeretheLora::MAX_IMAGES]
  end

  def test_trainer_version_is_pinned_not_floating
    assert_equal "ostris/flux-dev-lora-trainer", Studio::MeretheLora::TRAINER
    assert_match(/\A[0-9a-f]{64}\z/, Studio::MeretheLora::TRAINER_VERSION)
  end

  def test_preparation_is_local_only
    source = File.read(File.expand_path("../replicate/lora/merethe/prepare.rb", __dir__))
    refute_match(/train_lora|upload_zip|REPLICATE_API_TOKEN/, source)
  end
end
