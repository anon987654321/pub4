# frozen_string_literal: true

require_relative "test_helper"
require "open3"
require "json"
require "minitest/mock"

# The default English voice is Christopher; everyday speech is clean, and the
# named dilla profile restores the sound-design rack and room. The rack is data
# (voice.yml tts.dilla_fx), that file is its single source, and these tests run
# every filter through ffmpeg before it ships.
class TestDillaFx < Minitest::Test
  Policy = Master::Voice::Policy
  FFMPEG = system("ffmpeg", "-version", out: File::NULL, err: File::NULL)

  def with_env(pairs)
    saved = pairs.keys.to_h { |key| [key, ENV.fetch(key, nil)] }
    pairs.each { |key, value| ENV[key] = value }
    yield
  ensure
    saved.each { |key, value| ENV[key] = value }
  end

  def with_profile(name)
    saved = ENV.fetch("MASTER_TTS_PROFILE", nil)
    name ? ENV["MASTER_TTS_PROFILE"] = name : ENV.delete("MASTER_TTS_PROFILE")
    Policy.reload!
    yield
  ensure
    saved ? ENV["MASTER_TTS_PROFILE"] = saved : ENV.delete("MASTER_TTS_PROFILE")
    Policy.reload!
  end

  def ffmpeg_ok?(chain, seconds: 1)
    _out, status = Open3.capture2e("ffmpeg", "-hide_banner", "-loglevel", "error", "-f", "lavfi", "-i",
                                   "sine=f=220:d=#{seconds}:r=24000", "-af", chain, "-f", "null", "-")
    status.success?
  end

  def test_christopher_is_the_default_english_voice
    assert_equal :christopher, Policy.single_voice_key
    assert_equal "en-US-ChristopherNeural", Policy.neural_voice
    assert_equal [:christopher], Policy.rotation_keys
    assert_equal :christopher, Policy.language_voices.fetch("en")
    assert_equal :christopher, Master::Voice::Speech.default_voice if ENV["MASTER_TTS_VOICE"].to_s.empty?
    # Unhurried by operator order, 2026-10-20.
    assert_equal "-6%", Policy.default_rate
    assert_equal "+0Hz", Policy.default_pitch
    %w[single_voice neural].each { |key| refute_match(/jenny/i, Policy::FALLBACK.fetch(key)) }
    refute_includes Policy::FALLBACK.fetch("rotation"), "jenny"
  end

  def test_gender_and_language_locks_stay_coherent
    with_env("MASTER_TTS_GENDER" => nil) do
      assert_equal :christopher, Policy.voice_for_language(:en)
      assert_equal :pernille, Policy.voice_for_language(:nb)
      assert_equal :yasmin, Policy.voice_for_language(:ms)
    end
    with_env("MASTER_TTS_GENDER" => "female") { assert_equal :christopher, Policy.voice_for_language(:en) }
    with_env("MASTER_TTS_GENDER" => "male") do
      assert_equal :christopher, Policy.voice_for_language(:en)
      assert_equal :finn, Policy.voice_for_language(:nb)
    end
  end

  def test_jenny_is_retired_from_all_english_voice_selection
    voice = File.read(File.expand_path("../data/voice.yml", __dir__))
    top = voice[/^tts:\n(.*?)^  persona_affects_text_only/m, 1]
    refute_match(/jenny|JennyNeural/i, top)
    refute Master::Voice::Speech::VOICES.key?(:jenny)
    assert_equal :christopher, Master::Voice::Speech.resolve_voice(:jenny)
    assert_equal :christopher, Master::Voice::Speech.resolve_voice("en-US-JennyNeural")

    with_env("MASTER_TTS_VOICE" => "jenny", "MASTER_TTS_GENDER" => "female") do
      assert_equal :christopher, Master::Voice::Speech.default_voice
      assert_equal :christopher, Master::Voice::Speech.voice_for_text("I think this should work.")
    end

    face = File.read(File.expand_path("../../RAILS/master/public/face_speech_runtime.js", __dir__))
    refute_includes face, "|| 'en-US-JennyNeural'"
  end

  # Every unit names its stage and its status, and an approximation says why.
  def test_every_unit_has_a_unique_id_a_stage_and_a_status
    units = Policy.data.fetch("dilla_fx").fetch("units")
    ids = units.map { |unit| unit["id"] }
    assert_equal ids.uniq, ids, "a unit id is used twice"
    units.each do |unit|
      assert_includes %w[exact approximated unavailable], unit["status"], unit["id"]
      refute_empty unit["stage"].to_s, unit["id"]
      refute_empty unit["note"].to_s, "#{unit['id']} is #{unit['status']} and must say why" unless unit["status"] == "exact"
      assert unit["filter"].to_s.empty?, "#{unit['id']} is unavailable yet carries a filter" if unit["status"] == "unavailable"
      refute unit["enabled"], "#{unit['id']} is unavailable and must stay off" if unit["status"] == "unavailable"
    end
  end

  def test_the_rack_is_on_and_ordered_and_switchable
    with_profile("dilla") do
      assert Policy.fx_enabled?
      stages = Policy.fx_units.map { |unit| unit["stage"] }.uniq
      assert_equal %w[dynamics tone saturation modulation time stereo], stages
      chain = Policy.shaped_chain
      assert chain.start_with?(Policy.post_chain)
      assert_includes chain, "alimiter=limit=0.8:level=disabled"
      with_env("MASTER_TTS_FX" => "0") do
        refute Policy.fx_enabled?
        # The character presets voice.yml enables sit between the rack and the room.
        expected = [Policy.post_chain, Policy.character_chain, Policy.room_chain].compact.join(",")
        assert_equal expected, Policy.shaped_chain
        assert_equal({ enabled: false, units: [] }, Policy.fx_payload)
      end
      off = Policy.data.merge("dilla_fx" => Policy.fx_config.merge("enabled" => false))
      Policy.stub(:data, off) { refute Policy.fx_enabled? }
      one = Policy.fx_config.merge("units" => Policy.fx_config["units"].map { |u| u["id"] == "la2a" ? u.merge("enabled" => false) : u })
      Policy.stub(:data, Policy.data.merge("dilla_fx" => one)) do
        refute_includes Policy.fx_units.map { |u| u["id"] }, "la2a"
        assert_includes Policy.fx_units.map { |u| u["id"] }, "fet1176"
      end
    end
  end

  def test_asmr_human_and_dry_profiles_do_not_get_the_rack
    %w[asmr human dry].each do |name|
      with_env("MASTER_TTS_PROFILE" => name) do
        Policy.reload!
        refute Policy.fx_enabled?, name
      end
    end
  ensure
    with_env("MASTER_TTS_PROFILE" => nil) { Policy.reload! }
  end

  def test_the_payload_carries_the_rack_and_the_character_list
    with_profile("dilla") do
      payload = Policy.browser_payload
      assert_equal Policy.fx_units.size, payload.fetch(:dilla_fx).fetch(:units).size
      assert_equal({ in_db: -8.3 }, payload.fetch(:dilla_fx).slice(:in_db))
      enabled = Policy.character_names
      payload.fetch(:character).each do |preset|
        assert_includes enabled, preset[:id]
        assert_equal Policy.data["character"][preset[:id]]["filter"], preset[:filter]
      end
      runtime = File.read(File.expand_path("../../RAILS/master/public/face_speech_runtime.js", __dir__))
      assert_includes runtime, "function buildFxRack"
      assert_includes runtime, "MASTER_VOICE_POLICY?.dilla_fx"
    end
  end

  def test_the_whole_chain_runs_in_ffmpeg
    with_profile("dilla") do
      skip "ffmpeg missing" unless FFMPEG

      assert ffmpeg_ok?(Policy.shaped_chain, seconds: 2), "shaped_chain rejected by ffmpeg"
      Policy.fx_units.each do |unit|
        chain = unit["region"] == "stereo" ? "pan=stereo|c0=c0|c1=c0,#{unit['filter']}" : unit["filter"]
        assert ffmpeg_ok?(chain), "#{unit['id']} rejected by ffmpeg"
      end
    end
  end

  def test_peaks_stay_under_minus_one_dbtp_and_the_level_is_stable
    with_profile("dilla") do
      skip "ffmpeg missing" unless FFMPEG

      out, = Open3.capture2e("ffmpeg", "-hide_banner", "-nostats", "-f", "lavfi", "-i",
                             "sine=f=220:d=3:r=24000,tremolo=f=3:d=0.6", "-af", "#{Policy.shaped_chain},ebur128=peak=sample+true",
                             "-f", "null", "-")
      peaks = out.scan(/Peak:\s+(-?[\d.]+) dBFS/).flatten.map(&:to_f)
      refute_empty peaks
      assert_operator peaks.max, :<=, -1.0, "true peak #{peaks.max} dBFS"
      loudness = out.scan(/I:\s+(-?[\d.]+) LUFS/).last.first.to_f
      assert_operator loudness, :>, -40.0, "the rack swallowed the tone (#{loudness} LUFS)"
    end
  end

  # A preset is on when voice.yml enables it or MASTER_TTS_CHARACTER names it.
  def test_character_presets_are_off_unless_enabled_or_selected
    presets = Policy.data.fetch("character")
    assert_equal %w[robot formant doubler glitch shimmer ionosphere midnight shortwave], presets.keys

    with_env("MASTER_TTS_CHARACTER" => nil) do
      assert_equal presets.select { |_name, preset| preset["enabled"] }.keys, Policy.character_names
      refute_includes Policy.shaped_chain, "sin(2*PI*t*50)"
    end
    presets.each { |name, preset| assert_selected_preset(name, preset["filter"]) }
    %w[none bogus].each { |value| with_env("MASTER_TTS_CHARACTER" => value) { assert_empty Policy.character_names } }
  end

  def assert_selected_preset(name, filter)
    with_env("MASTER_TTS_CHARACTER" => name) do
      assert_equal [name], Policy.character_names
      assert_includes Policy.shaped_chain, filter
      assert ffmpeg_ok?(filter, seconds: 1), "#{name} rejected by ffmpeg" if FFMPEG
    end
  end
end
