# frozen_string_literal: true

require "fileutils"
require_relative "../test_helper"

class TestCharacterLoraZip < Minitest::Test
  def setup
    @tmpdir = File.join(Dir.tmpdir, "char_lora_zip_#{Process.pid}")
    FileUtils.mkdir_p(@tmpdir)
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  def test_validate_warns_when_below_recommended_min
    3.times do |index|
      File.write(File.join(@tmpdir, "img_#{index}.jpg"), "x" * 25_000)
    end
    report = Master::Reach::CharacterLoraZip.validate(@tmpdir, trigger_word: "zikigirl")
    assert_empty report[:issues]
    assert report[:warnings].any? { |warning| warning.include?("only 3 images") }
  end

  def test_zip_creates_captioned_archive
    2.times do |index|
      File.write(File.join(@tmpdir, "img_#{index}.jpg"), "x" * 25_000)
    end
    zip_path = File.join(@tmpdir, "train.zip")
    Master::Reach::CharacterLoraZip.zip(@tmpdir, zip_path, trigger_word: "zikigirl")
    assert File.exist?(zip_path)
    assert_operator File.size(zip_path), :>, 100
    listing = `unzip -l #{zip_path}`
    assert_includes listing, "a_photo_of_zikigirl_01.txt"
  end

  def test_validate_warns_for_identical_short_captions
    2.times do |index|
      image = File.join(@tmpdir, "img_#{index}.jpg")
      File.write(image, "x" * 25_000)
      File.write(File.join(@tmpdir, "img_#{index}.txt"), "a photo of zikigirl")
    end
    report = Master::Reach::CharacterLoraZip.validate(@tmpdir, trigger_word: "zikigirl")
    assert report[:warnings].any? { |warning| warning.include?("all captions are identical") }
    assert report[:warnings].any? { |warning| warning.include?("very short") }
  end
end
