# frozen_string_literal: true

require "yaml"
require "minitest/autorun"

ROOT = File.expand_path("..", __dir__)

class TestFutureFaceContract < Minitest::Test
  def setup
    @laws = YAML.safe_load_file(File.join(ROOT, "data", "laws.yml"), aliases: false)
    @morphology = @laws.fetch("interface").fetch("spatial").fetch("morphology")
  end

  def test_future_profile_uses_structural_traits_not_skin_or_identity_traits
    assert_equal "speculative_distant_human_2026", @morphology.fetch("model")
    assert_operator @morphology.fetch("cranium_scale"), :>, 1.0
    assert_operator @morphology.fetch("lower_face_scale"), :<, 1.0
    assert_operator @morphology.fetch("facial_projection"), :<, 1.0
    refute @morphology.key?("skin_tone")
    refute @morphology.key?("ethnicity")
  end

  def test_cli_and_web_read_the_same_morphology_contract
    head = File.read(File.join(ROOT, "lib", "cli", "face", "head.rb"))
    browser = File.read(File.join(ROOT, "web", "public", "face.part1.txt"))
    shader = File.read(File.join(ROOT, "web", "public", "face.part2.txt"))

    assert_includes head, 'Master::Face::Contract.spatial.fetch("morphology"'
    assert_includes browser, "FACE_MORPHOLOGY"
    assert_includes browser, "futureFeatureScale"
    assert_includes shader, "FACE_FUTURE_CRANIAL_HEIGHT"
    assert_includes shader, "FACE_FUTURE_FACIAL_PROJECTION"
  end

  def test_tts_polish_is_a_projection_not_a_second_speaker
    source = File.read(File.join(ROOT, "web", "public", "face_tts_polish.js"))
    manifest = File.read(File.join(ROOT, "web", "config", "face_assets.yml"))
    assert_includes source, "preservesPitch"
    assert_includes source, "MASTER_SPEECH_RUNTIME"
    assert_includes manifest, "face_tts_polish.js"
  end
end
