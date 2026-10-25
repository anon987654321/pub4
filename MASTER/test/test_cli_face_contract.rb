# frozen_string_literal: true

require "minitest/autorun"
require "yaml"

class CliFaceContractTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def read(path)
    File.read(File.join(ROOT, path))
  end

  def test_terminal_face_declares_supported_state_vocabulary
    face = read("lib/cli/face.rb")
    laws = read("data/laws.yml")

    %w[idle listening thinking working speaking warning error sleeping ready].each do |state|
      assert_includes face, state
    end

    assert_match(/STATES\s*=\s*%i\[idle listening thinking working speaking warning error sleeping ready\]/, face)
    assert_match(/terminal_law_ring:\s*true/, laws)
  end

  def test_terminal_depth_tones_are_neutral_and_motion_is_bounded
    tokens = YAML.safe_load_file(File.join(ROOT, "data", "tokens.yml"), aliases: true).fetch("tokens")
    ascii = tokens.fetch("face_interface").fetch("ascii")
    %w[tone_far tone_mid tone_near].each do |key|
      rgb = ascii.fetch(key).delete("#").scan(/../).map { |channel| channel.to_i(16) }
      assert_equal 3, rgb.size
      assert_equal rgb.first, rgb[1], "#{key} must be grayscale"
      assert_equal rgb.first, rgb[2], "#{key} must be grayscale"
    end
    motion = ascii.fetch("motion")
    assert_equal [0.28, 1.85], motion.fetch("glance_interval")
    assert_operator motion.fetch("glance_horizontal"), :<, 0.08
    assert_operator motion.fetch("glance_vertical"), :<, 0.04
  end

  def test_terminal_face_does_not_direct_voice_users_to_press_enter
    window = read("lib/cli/face/window.rb")
    refute_match(/listening[^\n]*enter to stop/i, window)
    assert_match(/listening[^\n]*say stop or type to interrupt/i, window)
  end
end
