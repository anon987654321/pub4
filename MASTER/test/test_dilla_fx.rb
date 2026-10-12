# frozen_string_literal: true

require_relative "test_helper"
require "open3"
require "json"
require "minitest/mock"

# The default English voice is Christopher, and the voice carries dilla's rack.
# The rack is data (voice.yml tts.dilla_fx); these tests hold it to dilla's own
# source so a default cannot be invented, and run the chain through ffmpeg so a
# filter this build rejects cannot ship.
class TestDillaFx < Minitest::Test
  Policy = Master::Voice::Policy
  SOUND = File.expand_path("../../STUDIO/dilla/lib/sound.rb", __dir__)
  FFMPEG = system("ffmpeg", "-version", out: File::NULL, err: File::NULL)

  def with_env(pairs)
    saved = pairs.keys.to_h { |key| [key, ENV.fetch(key, nil)] }
    pairs.each { |key, value| ENV[key] = value }
    yield
  ensure
    saved.each { |key, value| ENV[key] = value }
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
    assert_equal "+0%", Policy.default_rate
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
    with_env("MASTER_TTS_GENDER" => "female") { assert_equal :jenny, Policy.voice_for_language(:en) }
    with_env("MASTER_TTS_GENDER" => "male") do
      assert_equal :christopher, Policy.voice_for_language(:en)
      assert_equal :finn, Policy.voice_for_language(:nb)
    end
  end

  def test_no_data_file_reader_still_names_jenny_as_the_default
    voice = File.read(File.expand_path("../data/voice.yml", __dir__))
    top = voice[/^tts:\n(.*?)^  persona_affects_text_only/m, 1]
    refute_match(/single_voice: jenny|neural: en-US-JennyNeural|^    - jenny/, top)
    face = File.read(File.expand_path("../../RAILS/master_web/public/face_speech_runtime.js", __dir__))
    refute_includes face, "|| 'en-US-JennyNeural'"
  end

  # Every effect dilla owns has an entry, or the list below says why not.
  def dilla_effect_ids
    source = File.read(SOUND)
    outboard = source[/^module Outboard\n(.*?)^end\n/m, 1]
    units = outboard.scan(/^  def (\w+)/).flatten - %w[chain postpro_translation postpro_chain]
    stages = source[/STAGE_ORDER = %i\[([^\]]+)\]/, 1].split.map { |stage| "spacefx_#{stage}" }
    units + stages + %w[console_strip tape_hysteresis copy_machine low_pass_gate]
  end

  def test_every_dilla_effect_has_an_entry_with_a_status
    ids = Policy.data.fetch("dilla_fx").fetch("units").map { |unit| unit["id"] }
    missing = dilla_effect_ids.reject { |id| ids.include?(id) }
    # The Outboard methods dilla spells differently from their unit ids.
    assert_empty missing, "dilla effects with no entry in voice.yml dilla_fx: #{missing.join(', ')}"
    Policy.data.fetch("dilla_fx").fetch("units").each do |unit|
      assert_includes %w[exact approximated unavailable], unit["status"], unit["id"]
      refute_empty unit["note"].to_s, "#{unit['id']} is #{unit['status']} and must say why" unless unit["status"] == "exact"
      assert unit["filter"].to_s.empty?, "#{unit['id']} is unavailable yet carries a filter" if unit["status"] == "unavailable"
      refute unit["enabled"], "#{unit['id']} is unavailable and must stay off" if unit["status"] == "unavailable"
    end
  end

  def test_exact_outboard_units_are_dillas_own_defaults
    skip "dilla source missing" unless File.file?(SOUND)

    script = <<~RUBY
      require #{SOUND.inspect}
      require "json"
      out = {}
      Outboard.methods(false).each { |m| nil }
      %i[#{Policy.fx_units.filter_map { |u| u['source'][/Outboard\.(\w+)/, 1] if u['status'] == 'exact' }.uniq.join(' ')}].each do |unit|
        out[unit.to_s] = case unit
                         when :stc8 then Outboard.stc8(bpm: 0)
                         when :console_stack then Outboard.console_stack(instances: 3)
                         else Outboard.public_send(unit)
                         end
      end
      puts JSON.generate(out)
    RUBY
    out, status = Open3.capture2e(RbConfig.ruby, "-e", script)
    assert status.success?, out
    expected = JSON.parse(out.lines.last)
    Policy.fx_units.each do |unit|
      name = unit["source"][/Outboard\.(\w+)/, 1]
      next unless unit["status"] == "exact" && name

      defaults = unit.merge("level" => unit["level"])
      filter = Policy.fx_units.find { |row| row["id"] == unit["id"] }["filter"]
      assert_equal expected.fetch(name).gsub(/(\d)\.0\b/, "\\1"), filter.gsub(/(\d)\.0\b/, "\\1"), "#{unit['id']} drifted from dilla's default (#{defaults['level_name']})"
    end
  end

  def test_the_rack_is_on_and_ordered_and_switchable
    assert Policy.fx_enabled?
    stages = Policy.fx_units.map { |unit| unit["stage"] }.uniq
    assert_equal %w[dynamics tone saturation modulation time stereo], stages
    chain = Policy.shaped_chain
    assert chain.start_with?(Policy.post_chain)
    assert_includes chain, "alimiter=limit=0.8:level=disabled"
    with_env("MASTER_TTS_FX" => "0") do
      refute Policy.fx_enabled?
      assert_equal [Policy.post_chain, Policy.room_chain].join(","), Policy.shaped_chain
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
    payload = Policy.browser_payload
    assert_equal Policy.fx_units.size, payload.fetch(:dilla_fx).fetch(:units).size
    assert_equal({ in_db: -8.3 }, payload.fetch(:dilla_fx).slice(:in_db))
    assert_equal [], payload.fetch(:character)
    runtime = File.read(File.expand_path("../../RAILS/master_web/public/face_speech_runtime.js", __dir__))
    assert_includes runtime, "function buildFxRack"
    assert_includes runtime, "MASTER_VOICE_POLICY?.dilla_fx"
  end

  def test_the_whole_chain_runs_in_ffmpeg
    skip "ffmpeg missing" unless FFMPEG

    assert ffmpeg_ok?(Policy.shaped_chain, seconds: 2), "shaped_chain rejected by ffmpeg"
    Policy.fx_units.each do |unit|
      chain = unit["region"] == "stereo" ? "pan=stereo|c0=c0|c1=c0,#{unit['filter']}" : unit["filter"]
      assert ffmpeg_ok?(chain), "#{unit['id']} rejected by ffmpeg"
    end
  end

  def test_peaks_stay_under_minus_one_dbtp_and_the_level_is_stable
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

  def test_character_presets_are_off_unless_selected
    names = Policy.data.fetch("character").keys
    assert_equal %w[robot formant doubler glitch shimmer], names
    with_env("MASTER_TTS_CHARACTER" => nil) do
      assert_empty Policy.character_names
      assert_nil Policy.character_chain
      refute_includes Policy.shaped_chain, "sin(2*PI*t*50)"
    end
    names.each do |name|
      with_env("MASTER_TTS_CHARACTER" => name) do
        assert_equal [name], Policy.character_names
        assert_includes Policy.shaped_chain, Policy.data["character"][name]["filter"]
        assert ffmpeg_ok?(Policy.data["character"][name]["filter"], seconds: 1), "#{name} rejected by ffmpeg" if FFMPEG
      end
    end
    with_env("MASTER_TTS_CHARACTER" => "none") { assert_empty Policy.character_names }
    with_env("MASTER_TTS_CHARACTER" => "bogus") { assert_empty Policy.character_names }
  end
end
