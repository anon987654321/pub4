# frozen_string_literal: true

require "yaml"
require "minitest/autorun"

class TestFutureFaceContract < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def setup
    @tokens = YAML.safe_load_file(File.join(ROOT, "data", "tokens.yml"), aliases: true).fetch("tokens")
    @morphology = @tokens.fetch("face_interface").fetch("spatial").fetch("morphology")
  end

  def test_future_profile_uses_structural_traits_not_skin_or_identity_traits
    assert_equal "speculative_distant_human_2026_r3", @morphology.fetch("model")
    assert_operator @morphology.fetch("cranium_scale"), :>, 1.0
    assert_operator @morphology.fetch("lower_face_scale"), :<, 1.0
    assert_operator @morphology.fetch("facial_projection"), :<, 1.0
    assert_operator @morphology.fetch("facial_verticalization"), :>, 1.0
    assert_operator @morphology.fetch("masticatory_scale"), :<, 1.0
    assert_operator @morphology.fetch("upper_face_scale"), :<, 1.0
    assert_equal "neutral", @morphology.fetch("climate_variant")
    assert_operator @morphology.fetch("jaw_softening"), :>, 0.9
    assert_operator @morphology.fetch("malar_scale"), :>, 0.9
    refute @morphology.key?("skin_tone")
    refute @morphology.key?("ethnicity")
  end

  def test_cli_and_web_read_the_same_morphology_contract
    head = File.read(File.join(ROOT, "lib", "cli", "face", "head.rb"))
    browser = File.read(File.join(ROOT, "..", "RAILS", "master", "public", "face.part1.txt"))
    shader = File.read(File.join(ROOT, "..", "RAILS", "master", "public", "face.part2.txt"))

    assert_includes head, 'Master::Face::Contract.spatial.fetch("morphology"'
    assert_includes head, "FACIAL_VERTICALIZATION"
    assert_includes head, "MASTICATORY_SCALE"
    assert_includes browser, "FACE_MORPHOLOGY"
    assert_includes browser, "futureFeatureScale"
    assert_includes shader, "FACE_FUTURE_CRANIAL_HEIGHT"
    assert_includes shader, "FACE_FUTURE_FACIAL_PROJECTION"
    assert_includes shader, "FACE_FUTURE_VERTICALIZATION"
    assert_includes shader, "FACE_FUTURE_MASTICATORY"
    assert_includes shader, "futureSideBias"
  end

  def test_tts_polish_is_a_projection_not_a_second_speaker
    source = File.read(File.join(ROOT, "..", "RAILS", "master", "public", "face_tts_polish.js"))
    manifest = File.read(File.join(ROOT, "..", "RAILS", "master", "config", "face_assets.yml"))
    assert_includes source, "preservesPitch"
    assert_includes source, "MASTER_SPEECH_RUNTIME"
    assert_includes manifest, "face_tts_polish.js"
  end
end
