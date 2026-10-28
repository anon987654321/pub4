# frozen_string_literal: true

require_relative "../test_helper"

# The startup sound must never startle: these hold the measurable half of that promise (slow onsets, a fixed
# ceiling, the bells after the pad) on the score as voice.yml declares it.
class TestVoiceBootSound < Minitest::Test
  Sound = Master::Voice::BootSound
  def self.renders = @renders ||= {}

  def render(surface) = self.class.renders[surface] ||= Sound.render(Sound.config, surface:)

  def surface(name) = Sound.config.fetch("surfaces").fetch(name.to_s)

  def loudest(stereo) = stereo.transpose.map { |left, right| [left.abs, right.abs].max }

  def first_above(stereo, dbfs) = loudest(stereo).index { |sample| sample > 10**(dbfs / 20.0) }

  def milliseconds(frames) = frames * 1000.0 / Sound::RATE

  def test_each_surface_renders_its_length_in_stereo
    { cli: 2.2, web: 3.2 }.each do |name, seconds|
      stereo = render(name)

      assert_equal 2, stereo.size
      assert_in_delta seconds, stereo.first.size.to_f / Sound::RATE, 0.01
      assert_in_delta surface(name).fetch("seconds"), seconds, 0.01
    end
  end

  def test_nothing_is_audible_in_the_first_hundred_milliseconds
    %i[cli web].each do |name|
      assert_operator milliseconds(first_above(render(name), -40)), :>=, 100, "#{name} above -40 dBFS too soon"
      assert_operator milliseconds(first_above(render(name), -20) || Float::INFINITY), :>=, 250
    end
  end

  def test_the_peak_sits_at_the_surface_ceiling
    %i[cli web].each do |name|
      peak = 20 * Math.log10(loudest(render(name)).max)

      assert_operator peak, :<=, surface(name).fetch("ceiling_dbfs") + 0.01
      assert_operator peak, :>=, surface(name).fetch("ceiling_dbfs") - 0.1
    end
  end

  def test_the_bells_never_open_the_sound
    bells = Sound.config.dig("bells", "notes")
    pad = Sound.config.dig("pad", "notes")
    shift = surface(:cli).fetch("bells_shift_ms", 0)

    assert_operator bells.map { |note| note.fetch("at_ms") + shift }.min, :>=, 400
    assert_equal 0, pad.map { |note| note.fetch("at_ms") }.min
  end

  def test_the_render_is_deterministic_with_the_hiss_on
    assert_operator Sound.config.dig("tape", "hiss_dbfs"), :>, -120
    assert_equal render(:cli), Sound.render(Sound.config, surface: :cli)
  end

  def test_the_cache_key_follows_every_setting_and_the_surface
    settings = Sound.config
    key = Sound.cache_key(settings, surface: :cli)
    changed = %w[pad bells filter room tape master surfaces].map do |name|
      Sound.cache_key(settings.merge(name => { "changed" => name }), surface: :cli)
    end

    assert_equal 7, (changed - [key]).uniq.size
    refute_equal key, Sound.cache_key(settings, surface: :web)
    assert_equal key, Sound.cache_key(settings.merge("volume" => 0.2, "player" => "x"), surface: :cli)
  end

  def test_a_crush_leaves_few_levels_and_a_hold_halves_the_rate
    crushed = Array.new(200) { |i| Sound::Dsp.crush(Math.sin(i / 7.0), 3) }
    held = Sound::Dsp.hold((1..6).to_a, 2)

    assert_operator crushed.uniq.size, :<=, 9
    assert_equal [1, 1, 3, 3, 5, 5], held
  end

  def test_the_wav_is_interleaved_stereo
    stereo = render(:cli)
    bytes = Sound.wav(stereo)

    assert_equal "RIFF", bytes[0, 4]
    assert_equal "WAVE", bytes[8, 4]
    assert_equal 2, bytes[22, 2].unpack1("v")
    assert_equal 44 + (stereo.first.size * 4), bytes.bytesize
  end

  def test_the_face_gets_a_file_named_by_the_web_key
    payload = Sound.browser_payload

    assert_equal "boot_sound_#{Sound.cache_key(Sound.config, surface: :web)}.ogg", payload[:url]
    assert_equal surface(:web).fetch("late_gesture_s"), payload[:late_gesture_s]
    assert_equal Master::Voice::Policy.browser_payload[:boot_sound], payload
    assert_nil Sound.browser_payload(Sound.config.merge("enabled" => false))[:url]
  end

  def test_it_is_on_by_default_and_silent_with_the_switch
    assert_equal true, Sound.config["enabled"]
    previous = ENV["MASTER_BOOT_SOUND"]
    ENV["MASTER_BOOT_SOUND"] = "0"

    refute Sound.enabled?
  ensure
    previous.nil? ? ENV.delete("MASTER_BOOT_SOUND") : ENV["MASTER_BOOT_SOUND"] = previous
  end
end
