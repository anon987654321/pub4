# frozen_string_literal: true

require_relative "../test_helper"

class TestVoiceBootSound < Minitest::Test
  Sound = Master::Voice::BootSound

  def test_the_chime_is_about_a_second_of_samples_inside_full_scale
    samples = Sound.render(Sound.config)
    seconds = samples.size.to_f / Sound::RATE

    assert_in_delta 1.0, seconds, 0.25
    assert(samples.all? { |sample| sample.abs <= 1.0 })
    assert_operator samples.map(&:abs).max, :>, 0.05
  end

  def test_the_render_is_deterministic
    assert_equal Sound.render(Sound.config), Sound.render(Sound.config)
  end

  def test_a_crush_leaves_few_levels
    settings = Sound.config.merge("crush_bits" => 3)

    assert_operator Sound.render(settings).uniq.size, :<=, 9
  end

  def test_the_wav_has_a_riff_header_and_the_right_length
    samples = Sound.render(Sound.config)
    bytes = Sound.wav(samples)

    assert_equal "RIFF", bytes[0, 4]
    assert_equal "WAVE", bytes[8, 4]
    assert_equal 44 + (samples.size * 2), bytes.bytesize
  end

  def test_it_is_on_by_default_and_silent_with_the_switch
    assert_equal true, Sound.config["enabled"]
    ENV["MASTER_BOOT_SOUND"] = "0"

    refute Sound.enabled?
  ensure
    ENV.delete("MASTER_BOOT_SOUND")
  end
end
