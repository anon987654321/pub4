# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "open3"
require "rbconfig"
require "tmpdir"
require_relative "../dilla/dilla"

# Dilla has one Ruby source and versioned musical data.
# These tests hold the data to the shape the engine reads, the voicer to chord names, timing to
# its clamp, and the renderer to a smoke output in a temporary directory.
class DillaTest < Minitest::Test
  DIR = File.expand_path("../dilla", __dir__)
  SCRIPT = File.join(DIR, "dilla.rb")
  DATA = JSON.parse(File.read(File.join(DIR, "data", "dilla.json")))
  SHOWCASE = JSON.parse(File.read(File.join(DIR, "data", "showcase.json")))
  RECOVERED = JSON.parse(File.read(File.join(DIR, "data", "recovered_music.json")))
  PROGRESSIONS = DATA.fetch("progressions")
  CHORDS = PROGRESSIONS.flatten.uniq
  PLAYABLE = Playlist.new(DATA, Random.new(0)).voice_names # the rotation leaves out a soundfont voice with no soundfont

  # Measured at 20 s to 180 s each; DILLA_FAST=1 skips them with the CLI render tests.
  SLOW = %w[
    test_live_moves_run_inside_a_show_are_logged_and_leave_every_deck_as_it_was
    test_two_decks_play_eight_to_sixteen_bars_and_cross_over_two_to_four_on_the_bar_line
    test_the_new_profiles_render_stereo_in_blocks_the_same_as_whole
    test_a_pass_cut_into_blocks_is_the_pass_in_one_block
    test_the_show_starts_with_one_beat_then_plays_a_bar_at_a_time_and_joins_under_the_last_beat
    test_a_stack_keeps_the_programme_within_one_decibel_of_its_input_level
    test_mastering_is_deterministic
    test_a_show_that_cannot_keep_up_drops_the_dear_stages_and_says_so
  ].freeze

  def setup
    skip "slow (DILLA_FAST=1)" if ENV["DILLA_FAST"] == "1" && SLOW.include?(name)
  end

  # Mono unless a test asks for stereo: most tests read the samples of one channel.
  def run_dilla(*args, chdir:, stereo: false)
    skip "renders audio; unset DILLA_FAST to run it" if ENV["DILLA_FAST"] == "1"

    Open3.capture3(RbConfig.ruby, SCRIPT, *(stereo ? [] : ["--mono"]), *args, chdir:)
  end

  def sequencer(profile, pd_amount: nil, seed: 5, data: DATA)
    Sequencer.new(data, profile_name: profile, pd_amount:, seed:)
  end

  def with_fake_ffmpeg(directory, program)
    bin = File.join(directory, "bin")
    FileUtils.mkdir_p(bin)
    executable = File.join(bin, "ffmpeg")
    File.write(executable, "#!#{RbConfig.ruby}\n#{program}\n")
    File.chmod(0o755, executable)

    previous_path = ENV["PATH"]
    previous_postpro = ENV["DILLA_VIDEO_POSTPRO"]
    ENV["PATH"] = [bin, previous_path].compact.join(File::PATH_SEPARATOR)
    ENV["DILLA_VIDEO_POSTPRO"] = "0"
    yield
  ensure
    previous_path.nil? ? ENV.delete("PATH") : ENV["PATH"] = previous_path
    previous_postpro.nil? ? ENV.delete("DILLA_VIDEO_POSTPRO") : ENV["DILLA_VIDEO_POSTPRO"] = previous_postpro
  end

  def offsets_from_grid(hits, role, step)
    hits.select { |r, _| r == role }.map { |_, t| t - ((t / step).round * step) }
  end

  # ------------------------------------------------------------- the files

  def test_the_tracked_tree_is_the_engine_its_data_and_a_readme
    tracked, status = Open3.capture2("git", "ls-files", ".", chdir: DIR)
    skip "not a git checkout" unless status.success?
    assert_equal %w[.gitignore ENGINE_NOTES.md README.md REFERENCE_STUDY.md data/dilla.json data/music_theory.json data/recovered_music.json data/showcase.json dilla.rb dilla.wav], tracked.lines.map(&:strip).sort
  end

  def test_no_artist_band_song_or_book_is_named_anywhere
    banned = /slum|village|madlib|lotus|flylo|coltrane|miles davis|hancock|herbie|jamal|d'angelo|badu|\bsade\b|stevie|marvin|gaye|thundercat|questlove|voodoo|donuts|fantastic|charnas|ethan hein|burton|theseus|james brown|mayfield|j dilla|jay dee|eddie harris|bill evans/i
    %w[dilla.rb data/dilla.json data/showcase.json README.md].each do |file|
      text = File.read(File.join(DIR, file))
      # These two words occur only inside recovered study IDs, not artist references.
      text = text.gsub(/\b(?:burton_flip|theseus_microtiming)\b/, "")
      assert_nil text[banned], "#{file} names #{text[banned].inspect}"
    end
  end

  def test_list_exposes_the_recovered_harmonic_and_named_heritage_presets
    stdout, stderr, status = run_dilla("--list", chdir: DIR)
    assert status.success?, stderr
    %w[j5_donut_loop relative_answer dorian_four flexible_sixth mediant_lift].each do |name|
      assert_includes stdout, name
    end
    %w[dilla_life neo_soul dreamscape floating soulquarian donut_shop slum_village ethiojazz ahmad_jamal isley_brothers].each do |name|
      assert_includes stdout, name
    end
    %w[get_dis_money burton_flip dont_cry_ii_add11 dilla_inversion theseus_microtiming].each do |name|
      assert_includes stdout, name
    end
  end

  def test_recovered_inversion_pattern_and_theseus_lane_offsets_are_live_data
    pattern = DATA.fetch("drum_patterns").fetch("dilla_inversion")
    assert_equal [0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0], pattern.fetch("kick")
    assert_equal [0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0], pattern.fetch("snare")
    assert_equal [0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1], pattern.fetch("hat")
    profile = DATA.fetch("groove_profiles").fetch("theseus_microtiming")
    assert_equal({ "kick" => 0.012, "kick_first" => 0.0, "snare" => -0.010, "hat" => 0.015 }, profile.fetch("offsets"))
    assert_equal "dilla_inversion", profile.fetch("drums")
  end

  def test_named_harmonic_studies_keep_their_source_and_confidence_labels
    studies = RECOVERED.fetch("named_studies")
    assert_equal %w[burton_flip dilla_inversion dont_cry_ii_add11 get_dis_money theseus_microtiming], studies.keys.sort
    assert_equal 7, studies.fetch("get_dis_money").fetch("phrase_bars")
    assert_equal(-4, studies.fetch("get_dis_money").fetch("sample_pitch_shift_semitones"))
    assert_equal 50, studies.fetch("get_dis_money").fetch("bass_tuning_cents")
    assert_equal %w[B7b9 F7#11 E9sus4], studies.fetch("burton_flip").fetch("chords")
    assert_equal "low_confidence_harmonic_research_lead", studies.fetch("dont_cry_ii_add11").fetch("status")
    assert_equal "proposed_deterministic_timing_model_not_audio_measurement", studies.fetch("theseus_microtiming").fetch("status")
  end

  def test_pub3_analog_pad_and_vintage_effect_research_is_preserved
    groups = RECOVERED.fetch("legacy_progression_groups")
    assert_equal 15, groups.fetch("iconic_pad_synthesis").size
    assert_equal 11, groups.fetch("vintage_fx_chains").size
    assert groups.fetch("iconic_pad_synthesis").values.all? { |row| row.key?("synth") && row.key?("envelope") }
    assert groups.fetch("vintage_fx_chains").values.all? { |row| row.key?("description") && (row.key?("sox_chain") || row.key?("ffmpeg_chain") || row.key?("sox_chain_template")) }
  end

  def test_recovered_harmonic_languages_are_playable_and_transposable
    expected = %w[j5_donut_loop relative_answer dorian_four flexible_sixth mediant_lift]
    assert_empty expected - Languages.names
    expected.each do |name|
      progression = Languages.progression(name)
      assert_operator progression.length, :>=, 2
      assert progression.all? { |chord| Chords.parse(chord) }
      assert_equal progression, Languages.progression(name, tonic: Languages::TONIC)
      assert_equal progression.length, KeyLock.lock(progression, "Bb").length
    end
    assert_equal "Ebmaj7", Languages.progression("j5_donut_loop").first
  end

  def test_recovered_historical_presets_keep_their_names_tempo_and_playable_chords
    presets = RECOVERED.fetch("legacy_presets")
    assert_equal 10, presets.size
    presets.each do |name, preset|
      assert_match(/\A[a-z_]+\z/, name)
      assert_operator preset.fetch("tempo"), :>=, 60
      assert_operator preset.fetch("tempo"), :<=, 160
      assert_equal 4, preset.fetch("chords").size
      preset.fetch("chords").each { |chord| assert Chords.parse(chord), "#{name}: #{chord}" }
      assert_equal "historical_style_preset_not_verified_transcription", preset.fetch("status")
      assert preset.fetch("legacy_fx")
    end
  end

  def test_random_take_uses_the_dilla_output_override
    Dir.mktmpdir do |dir|
      previous = ENV["DILLA_OUTPUT_DIR"]
      begin
        ENV["DILLA_OUTPUT_DIR"] = dir
        options = { seed: 123 }

        capture_io { randomize_take!(DATA, options) }

        assert_equal dir, File.dirname(options.fetch(:out))
        assert_match(/\Adilla-\d{6}-123\.wav\z/, File.basename(options.fetch(:out)))
      ensure
        previous.nil? ? ENV.delete("DILLA_OUTPUT_DIR") : ENV["DILLA_OUTPUT_DIR"] = previous
      end
    end
  end

  def test_default_layers_fill_out_profiles_without_overriding_specialists
    layers = DATA.fetch("default_layers")
    assert_equal %w[dub_bass dx_ep_glass prophet_warm], layers.map { |layer| layer.fetch("voice") }.sort
    assert layers.any? { |layer| layer["notes"] == "bass" }
    assert layers.any? { |layer| layer["mode"] == "arp" }

    assert_equal layers, sequencer("straight_hats_snare_ahead").profile_layers
    %w[new_age techno_arp industrial_arp pure_tone_dry].each do |profile|
      assert_empty sequencer(profile).profile_layers, profile
    end
    assert_includes DATA.fetch("play_profiles"), "dilla_shadow"
    assert_equal "dilla_shadow_full", DATA.fetch("groove_profiles").fetch("dilla_shadow").fetch("drums")
    assert_equal "kit_dust", DATA.fetch("groove_profiles").fetch("dilla_shadow").fetch("kit")
  end

  def test_the_data_has_only_what_the_engine_reads
    assert_equal %w[ambient arp bus_effects comp default_layers default_profile drum_patterns echo essential groove_profiles kick_styles kits master mix modal_patches nasty_vcs noise organ play_profiles progressions sonitex stages stereo strum tape voices], DATA.keys.sort
  end

  def test_showcase_uses_dark_harmony_with_a_leaner_mix_and_dilla_drums
    sections = SHOWCASE.fetch("sections")
    assert_equal 8, sections.size
    assert_equal "Blue Hour — Dilla Minor Dub Cut", SHOWCASE.fetch("title")
    sections.each do |section|
      assert_equal 92, section.fetch("bpm")
      allowed = section.fetch("scale_pcs")
      assert(section.fetch("progression").all? { |name| Chords.parse(name) })
      section.fetch("progression").each do |name|
        chord = Chords.parse(name)
        pitch_classes = chord.fetch(:tones).map { |tone| (chord.fetch(:pc) + tone) % 12 }
        pitch_classes.concat([chord.fetch(:bass)]) if chord.fetch(:bass)
        assert_empty pitch_classes.uniq - allowed, "#{section.fetch('name')} #{name} leaves its named scale"
      end
      section.fetch("melody").each do |beat, midi, length, gain|
        assert_operator beat, :>=, 0
        assert_includes allowed, midi % 12, "#{section.fetch('name')} melody leaves its scale"
        assert_operator length, :>, 0
        assert_operator gain, :>, 0
        assert_operator gain, :<=, 1
      end
      assert_includes DATA.fetch("voices").keys, section.fetch("voice")
      assert_includes DATA.fetch("voices").keys, section.fetch("melody_voice")
      assert_includes DATA.fetch("groove_profiles").keys, section.fetch("profile")
      assert_equal "dilla_shadow", section.fetch("profile")
      assert_includes DATA.fetch("drum_patterns").keys, section.fetch("drums")
      assert_includes DATA.fetch("comp").fetch("styles").keys, section.fetch("repeat")
      assert_includes DATA.fetch("sonitex").fetch("presets").keys, section.fetch("sonitex")
      assert_operator section.fetch("sonitex_instances"), :>=, 1
      assert_operator section.fetch("sonitex_instances"), :<=, 2
      assert_equal "kit_dust", section.fetch("kit")
      assert_includes DATA.fetch("kits").keys, section.fetch("kit")
      assert_equal false, section.fetch("echo")
      assert_equal 0, section.fetch("echo_reverb")
      if section.fetch("name") == "Nylon Room"
        assert_equal "nylon_guitar", section.fetch("voice")
        assert_equal "steel_guitar", section.fetch("melody_voice")
        assert_empty section.fetch("layers"), "the guitar feature remains a deliberate lean arrangement"
      else
        assert_equal "rhodes_mark1", section.fetch("voice")
        assert_equal "rhodes_tine_wurli", section.fetch("melody_voice")
        assert_equal 2, section.fetch("layers").size
        layer_voices = section.fetch("layers").map { |layer| layer.fetch("voice") }
        assert_empty %w[prophet_warm dub_bass] - layer_voices
        assert(section.fetch("layers").any? { |layer| layer["notes"] == "bass" }, "a low-end bass layer is required")
        families = layer_voices.map { |name| DATA.fetch("voices").fetch(name).fetch("family") }.uniq
        assert_includes families, "moog"
        section.fetch("layers").each do |layer|
          assert_includes DATA.fetch("voices").keys, layer.fetch("voice")
          assert_equal 0, layer.fetch("transpose", 0) % 12
        end
      end
      texture = DATA.fetch("groove_profiles").fetch(section.fetch("profile")).fetch("texture")
      assert_equal 0, texture.fetch("detune")
      assert_equal 0, texture.fetch("reverb")
      hats = DATA.fetch("drum_patterns").fetch(section.fetch("drums")).fetch("hat")
      assert_equal 16, hats.size
      assert_equal 16, hats.count { |velocity| velocity.to_f.positive? }, "the fast hat keeps its sixteenth-note pulse"
      assert_operator hats.uniq.size, :>, 2, "hat velocities create accents instead of a flat machine-gun"
      rig = DATA.fetch("bus_effects").fetch(section.fetch("effect_rig"))
      assert_equal "cassette", rig.fetch("drum_sonitex")
      assert_equal "dilla_bed", section.fetch("effect_rig")
      assert_equal 1, rig.fetch("drum_sonitex_instances")
      assert_equal "light", rig.fetch("drum_tape")
      assert_operator rig.fetch("drum_vcs"), :<=, 0.4
      dub = rig.fetch("drum_dub_echo")
      assert_equal [1, 2], dub.fetch("heads")
      assert_operator dub.fetch("intensity"), :<=, 0.3
      assert_operator dub.fetch("volume"), :<=, 0.3
      assert_operator dub.fetch("saturation"), :<=, 0.2
      assert_equal 0, dub.fetch("reverb")
      %w[clap open rim perc tom].each do |role|
        assert_equal 16, DATA.fetch("drum_patterns").fetch(section.fetch("drums")).fetch(role).size
      end
      assert section.fetch("drums").end_with?("_full"), "showcase uses the expanded kit pattern only"
      crystal = rig.fetch("drum_crystallizer")
      assert_equal 12, crystal.fetch("semitones")
      assert_operator crystal.fetch("mix"), :<=, 0.05
      assert_equal 1, crystal.fetch("repeats")
      assert_equal 0, rig.dig("instrument_dub_echo", "reverb")
    end
    refute_equal SHOWCASE.fetch("sections").first.fetch("progression"),
                 SHOWCASE.fetch("sections").last.fetch("progression")
  end

  def test_named_effect_rig_supplies_processing_defaults_from_canonical_data
    options = { effect_rig: "dilla_night" }
    apply_effect_rig!(options, DATA)
    rig = DATA.fetch("bus_effects").fetch("dilla_night")

    assert_equal rig.fetch("drum_sonitex"), options.fetch(:drum_sonitex)
    assert_equal rig.fetch("drum_sonitex_instances"), options.fetch(:drum_sonitex_instances)
    assert_equal rig.fetch("drum_tape"), options.fetch(:drum_tape)
    assert_equal rig.fetch("drum_vcs"), options.fetch(:drum_vcs)
    assert_equal rig.fetch("drum_dub_echo"), options.fetch(:drum_dub_echo)
    assert_equal rig.fetch("drum_crystallizer"), options.fetch(:drum_crystallizer)
    assert_equal rig.fetch("instrument_dub_echo"), options.fetch(:instrument_dub_echo)
    assert_equal rig.fetch("instrument_crystallizer"), options.fetch(:instrument_crystallizer)
  end

  def test_named_effect_rig_preserves_explicit_operator_overrides
    options = { effect_rig: "dilla_night", drum_tape: "light" }
    apply_effect_rig!(options, DATA)

    assert_equal "light", options.fetch(:drum_tape)
    assert_equal DATA.fetch("bus_effects").fetch("dilla_night").fetch("drum_crystallizer"), options.fetch(:drum_crystallizer)
  end

  def test_default_output_paths_are_one_fixed_pair_beside_the_engine
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "dilla.wav"), "replaced on the next run")

      paths = Dilla::Video.default_paths(root: dir)

      assert_equal File.join(dir, "dilla.wav"), paths.fetch(:audio)
      assert_equal File.join(dir, "dilla.mp4"), paths.fetch(:video)
    end
  end

  def test_video_filter_graph_labels_background_without_an_empty_filter
    graph = Dilla::Video.filter_graph

    assert_match(/drawbox=x=116:y=108:w=1048:h=504:color=0x203b56@0\.95:t=1\[base\]/, graph)
    refute_includes graph, ",[base]"
    assert_match(/\[0:a\]showwaves=.*\[wave\]/, graph)
    assert_match(/\[base\]\[wave\]overlay=.*format=yuv420p\[v\]\z/, graph)
  end

  def test_video_render_installs_a_complete_mp4_without_overwriting_a_take
    Dir.mktmpdir do |dir|
      audio = File.join(dir, "source.wav")
      target = File.join(dir, "render.mp4")
      File.binwrite(audio, "wav fixture")

      with_fake_ffmpeg(dir, 'File.binwrite(ARGV.last, "fake mp4 payload")') do
        result = nil
        capture_io { result = Dilla::Video.render(audio:, output: target) }

        assert_equal target, result
        assert_equal "fake mp4 payload", File.binread(target)
        assert_empty Dir.glob(File.join(dir, ".*.tmp.mp4"))

        error = assert_raises(Dilla::Video::Error) do
          Dilla::Video.render(audio:, output: target)
        end
        assert_match(/refusing to overwrite existing MP4/, error.message)
      end
    end
  end

  def test_video_render_failure_preserves_audio_and_removes_temporary_output
    Dir.mktmpdir do |dir|
      audio = File.join(dir, "source.wav")
      target = File.join(dir, "render.mp4")
      File.binwrite(audio, "wav fixture")

      with_fake_ffmpeg(dir, 'warn "controlled ffmpeg failure"; exit 17') do
        error = assert_raises(Dilla::Video::Error) do
          Dilla::Video.render(audio:, output: target)
        end

        assert_match(/ffmpeg exit=17: controlled ffmpeg failure/, error.message)
        assert_equal "wav fixture", File.binread(audio)
        refute File.exist?(target)
        assert_empty Dir.glob(File.join(dir, ".*.tmp.mp4"))
      end
    end
  end

  def test_showcase_tempo_schedule_is_repeatable_and_stays_within_92_to_116_bpm
    first = showcase_tempos(seed: 261_013, count: 8)
    assert_equal first, showcase_tempos(seed: 261_013, count: 8)
    assert_operator first.min, :>=, 92
    assert_operator first.max, :<=, 116
    assert_operator first.uniq.size, :>=, 7
    first.each_cons(2) { |left, right| refute_equal left, right }
  end

  def test_default_run_renders_the_showcase_as_a_wav
    Dir.mktmpdir do |dir|
      out = File.join(dir, "blue-hour.wav")
      stdout, stderr, status = run_dilla("--no-video", "--out", out, chdir: dir)
      assert status.success?, "render failed\n#{stdout}\n#{stderr}"
      assert_includes stdout, "Blue Hour"
      assert File.file?(out), "renderer did not create the WAV"
      header = File.binread(out, 44)
      assert_equal "RIFF", header.byteslice(0, 4)
      assert_equal "WAVE", header.byteslice(8, 4)
      assert_equal 44_100, header.byteslice(24, 4).unpack1("V")
      assert_operator File.size(out), :>, 44
    end
  end

  def test_default_layers_and_full_dilla_drum_kit_render_on_a_normal_pass
    Dir.mktmpdir do |dir|
      out = File.join(dir, "dilla-full-kit.wav")
      stdout, stderr, status = run_dilla(
        "--progression", "2",
        "--profile", "dilla_shadow",
        "--effect-rig", "dilla_night",
        "--beats", "1",
        "--bpm", "92",
        "--seed", "31",
        "--out", out,
        chdir: dir
      )

      assert status.success?, "enriched progression failed\n#{stdout}\n#{stderr}"
      assert_includes stdout, "drums=dilla_shadow_full"
      assert File.file?(out), "renderer did not create the enriched WAV"
      header = File.binread(out, 44)
      assert_equal "RIFF", header.byteslice(0, 4)
      assert_equal "WAVE", header.byteslice(8, 4)
      assert_operator File.size(out), :>, 44
    end
  end

  def test_stereo_interleave_preserves_order_and_legacy_zip_shape
    assert_equal [1, 4, 2, 5, 3, 6], Stereo.interleave([[1, 2, 3], [4, 5, 6]])
    assert_equal [1, 4, 2, nil], Stereo.interleave([[1, 2], [4]])
    assert_equal [1, 4, 2, 5], Stereo.interleave([[1, 2], [4, 5, 6]])

    mono = [1, 2, 3]
    assert_same mono, Stereo.interleave([mono])
  end

  def test_block_wav_writer_matches_whole_writer_for_mono_stereo_and_both_bit_depths
    fixtures = [
      [0.0, -1.0, -0.25, 0.125, 0.5, 0.999, 1.0],
      [[0.0, -1.0, -0.25, 0.125, 0.5, 0.999, 1.0], [1.0, 0.5, 0.25, -0.125, -0.5, -0.999, -1.0]]
    ]

    Dir.mktmpdir do |dir|
      fixtures.each_with_index do |samples, fixture_index|
        channels = samples.first.is_a?(Array) ? samples : [samples]
        [16, 24].each do |bits|
          whole = File.join(dir, "whole-#{fixture_index}-#{bits}.wav")
          streamed = File.join(dir, "streamed-#{fixture_index}-#{bits}.wav")
          WAV.write(whole, samples, bits:)
          WAV.write_stream(streamed, frames: channels.first.size, channels: channels.size, bits:, block_size: 3) do |offset, count|
            channels.map { |channel| channel.slice(offset, count) }
          end

          assert_equal File.binread(whole), File.binread(streamed), "fixture=#{fixture_index} bits=#{bits}"
        end
      end
    end
  end

  def test_stream_wav_writer_explicit_replace_preserves_existing_mode
    Dir.mktmpdir do |dir|
      path = File.join(dir, "take.wav")
      File.binwrite(path, "old take")
      File.chmod(0o640, path)

      WAV.write_stream(path, frames: 3, channels: 1, replace: true) do |_offset, count|
        [Array.new(count, 0.25)]
      end

      assert_equal 0o640, File.stat(path).mode & 0o777
      assert_equal "RIFF", File.binread(path, 4)
    end
  end

  def test_wav_writer_preserves_an_existing_take_unless_replace_is_explicit
    Dir.mktmpdir do |dir|
      path = File.join(dir, "take.wav")
      WAV.write(path, [0.25, -0.25])
      original = File.binread(path)

      error = assert_raises(ArgumentError) { WAV.write(path, [-0.5, 0.5]) }
      assert_match(/refusing to overwrite existing take/, error.message)
      assert_equal original, File.binread(path), "a failed replacement must leave the take byte-for-byte intact"

      WAV.write(path, [-0.5, 0.5], replace: true)
      refute_equal original, File.binread(path)
    end
  end

  def test_midi_writer_uses_the_same_no_overwrite_contract
    Dir.mktmpdir do |dir|
      path = File.join(dir, "take.mid")
      MIDI.write(path, %w[Cm9 Fm9], 92, 8, [])
      original = File.binread(path)

      assert_raises(ArgumentError) { MIDI.write(path, %w[Cm9 Fm9], 96, 8, []) }
      assert_equal original, File.binread(path)

      MIDI.write(path, %w[Cm9 Fm9], 96, 8, [], replace: true)
      refute_equal original, File.binread(path)
    end
  end

  def test_render_preflight_refuses_an_existing_output_unless_replace_is_explicit
    Dir.mktmpdir do |dir|
      path = File.join(dir, "protected.wav")
      original = "keep this take intact"
      File.binwrite(path, original)

      _stdout, stderr, status = run_dilla("--quick", "--out", path, chdir: dir)
      refute status.success?
      assert_match(/refusing to overwrite existing take/, stderr)
      assert_equal original, File.binread(path)

      stdout, err, status = run_dilla("--quick", "--out", path, "--replace", chdir: dir)
      assert status.success?, "explicit replacement failed\n#{stdout}\n#{err}"
      refute_equal original, File.binread(path)
    end
  end

  # ------------------------------------------------------------- progressions

  def test_progressions_are_a_flat_array_of_chord_name_arrays_without_duplicates
    assert_operator PROGRESSIONS.size, :>, 90
    assert(PROGRESSIONS.all? { |p| p.is_a?(Array) && p.size >= 2 && p.all? { |c| c.is_a?(String) } })
    assert_equal PROGRESSIONS.map { |p| p.join(" ") }.uniq.size, PROGRESSIONS.size, "a spelling appears twice"
  end

  def test_key_lock_moves_roots_and_basses_and_keeps_qualities
    # the last chord rests on G, so every root moves up three semitones and the slash bass with it
    assert_equal %w[Gm9 Cm9 Bbmaj7/G], KeyLock.lock(%w[Em9 Am9 Gmaj7/E], "Bb")
    assert_equal %w[Ebm9 Bbm9], KeyLock.lock(%w[Ebm9 Bbm9], "Bb")
    assert_equal "E", KeyLock.tonic(%w[D/E Db/E C/E Bm/E Bbm/E Am/E])
    assert_equal ["Bbm69"], KeyLock.lock(["Dm6/9"], "Bb")
  end

  def test_every_catalogue_progression_locks_and_scores_a_fit
    PROGRESSIONS.each do |names|
      assert_equal names.size, KeyLock.lock(names, "Bb").size
      assert_includes 0.0..1.0, ModalFamily.fit(names)
    end
  end

  def test_lead_and_bass_lines_follow_the_chords_and_replay_from_a_seed
    names = Languages.progression("planing_m9")
    lead = Lines.lead(names, beats: 4, seed: 9)
    bass = Lines.bass(names, beats: 4, seed: 9)
    assert_equal lead, Lines.lead(names, beats: 4, seed: 9)
    assert_operator lead.size, :>=, names.size * 3
    assert(lead.all? { |beat, midi, length, gain| beat >= 0 && midi.between?(60, 90) && length.positive? && gain.positive? })
    assert(bass.all? { |_, midi, _, _| midi.between?(Lines::BASS_LOW, Lines::BASS_HIGH + 12) })
    assert_equal Chords.parse(names.first)[:pc], bass.first[1] % 12
  end

  def test_critic_prefers_a_warm_falling_spectrum_to_white_noise
    rng = Random.new(1)
    white = Array.new(SAMPLE_RATE * 2) { (rng.rand - 0.5) * 0.4 }
    low = Tape::Biquad.lowpass(900)
    warm = white.map { |x| low.step(x) * 3.0 }
    assert_operator Critic.score(Critic.measure([warm])), :<, Critic.score(Critic.measure([white]))
  end

  def test_guitar_voices_are_plucked_strings_in_tune_that_die_away_and_replay
    %w[nylon_guitar steel_guitar muted_guitar clean_electric].each do |name|
      spec = DATA.fetch("voices").fetch(name).merge("name" => name)
      assert_equal "string", spec.fetch("family")
      note = Voices.note(spec, 57, 1.0, 0.3)
      assert_equal note, Voices.note(spec, 57, 1.0, 0.3), "#{name} is the same note each time"
      assert_operator note.map(&:abs).max, :<, 1.0, name
      period = SAMPLE_RATE / Chords.hz(57)
      segment = note[2000, 8000]
      lags = ((period.round - 3)..(period.round + 3)).to_a
      scores = lags.map { |lag| (0...4000).sum { |i| segment[i] * segment[i + lag] } }
      k = scores.each_index.max_by { |i| scores[i] }
      y0, y1, y2 = scores[k - 1], scores[k], scores[k + 1]
      lag = lags[k] + (0.5 * (y0 - y2) / (y0 - (2 * y1) + y2))
      assert_in_delta 0.0, 1200 * Math.log2(period / lag), 3.0, "#{name} is within three cents of A3"
      early = note[3000, 2000].map(&:abs).max
      late = note[(SAMPLE_RATE * 0.8).to_i, 2000].map(&:abs).max
      assert_operator late, :<, early, "#{name} dies away"
    end
  end

  def test_every_language_chord_parses_and_stays_in_the_register
    Languages.all.each do |language, names|
      assert_equal 8, names.size, language
      Chords.midi_notes(names).each do |notes|
        assert_operator notes.first, :>=, 24, language
        assert_operator notes.last, :<=, Chords::HIGH, language
      end
    end
  end

  def test_voicing_styles_reshape_a_chord_and_restore_the_default
    names = %w[Bbm9 Ebm9 Abmaj9]
    plain = Chords.midi_notes(names)
    Chords::STYLES.each do |style|
      styled = Chords.styled(style) { Chords.midi_notes(names) }
      refute_equal plain, styled, style
      styled.each { |notes| assert_operator notes.drop(1).first, :>=, Chords::LOW, style }
    end
    assert_equal plain, Chords.midi_notes(names)
    assert_raises(ArgumentError) { Chords.styled("bebop") { nil } }
  end

  def test_so_what_voicing_is_fourths_under_a_major_third
    upper = Chords.styled("so_what") { Chords.midi_notes(["Bbm9"]) }.first.drop(1)
    assert_equal [5, 5, 4], upper.each_cons(2).map { |a, b| b - a }
  end

  def test_every_chord_name_parses
    CHORDS.each { |name| Chords.parse(name) }
  end

  def test_the_voicer_reads_the_extended_chords_it_is_given
    assert_equal [0, 3, 7, 10, 14], Chords.parse("Cm9")[:tones]
    assert_equal [0, 4, 7, 11, 14], Chords.parse("Cmaj9")[:tones]
    assert_equal [0, 4, 7, 10, 14, 21], Chords.parse("C13")[:tones]
    assert_equal [0, 4, 7, 17], Chords.parse("Cadd11")[:tones]
    assert_equal [0, 5, 7, 10, 14], Chords.parse("C9sus4")[:tones]
    assert_equal [0, 3, 6, 10], Chords.parse("Cm7b5")[:tones]
    assert_equal [0, 4, 7, 10, 15], Chords.parse("C7#9")[:tones]
    parsed = Chords.parse("Bbm/E")
    assert_equal [10, 4], [parsed[:pc], parsed[:bass]]
    assert_raises(ArgumentError) { Chords.parse("H7") }
    assert_raises(ArgumentError) { Chords.parse("Cfoo") }
  end

  # What a chord must keep: the third or sus tone, the sixth or seventh and every named
  # extension, as pitch classes. The root or the slash bass is the lowest note.
  def required_pcs(chord)
    chord[:tones].select { |t| [2, 3, 4, 5, 9, 10, 11].include?(t) || t >= 13 }.map { |t| (chord[:pc] + t) % 12 }
  end

  # Maps each voicing's pitch classes back to the chord spelling: nothing outside the chord and
  # its slash bass sounds, the lowest note is the root or the bass, and the third, the sus tone,
  # the seventh and the named extension are there. Run with and without the search.
  def test_every_voicing_maps_back_to_its_chord_spelling
    previous_chords = [nil, [40, 60, 64, 67], [46, 64, 70, 73, 77], [38, 57, 74, 77]]
    CHORDS.each do |name|
      chord = Chords.parse(name)
      bass_pc = chord[:bass] || chord[:pc]
      chord_pcs = chord[:tones].map { |t| (chord[:pc] + t) % 12 }
      previous_chords.product([true, false]).each do |previous, search|
        notes = Chords.voice(name, previous, search:)
        upper = notes.drop(1)
        assert_equal bass_pc, notes.first % 12, "#{name}: the lowest note is the root or the slash bass"
        assert_operator notes.first, :<, 48, "#{name}: the bass is in the low octave"
        assert(notes.all? { |n| (chord_pcs + [bass_pc]).include?(n % 12) }, "#{name}: #{notes} has a note the spelling does not")
        assert_operator notes.size, :<=, [Chords::MAX_VOICES, 1 + required_pcs(chord).uniq.size].max, "#{name}: too many voices"
        assert(upper.all? { |n| n.between?(52, 84) }, "#{name}: upper structure out of range #{notes}")
        assert(upper.each_cons(2).none? { |a, b| b - a <= 1 }, "#{name}: a duplicate or a minor second rubs")
      end
    end
  end

  # (a) Every chord of all 105 progressions keeps its essential tones, however it is led to.
  def test_no_voicing_loses_a_chord_tone_in_any_progression
    PROGRESSIONS.each_with_index do |names, index|
      [true, false].each do |search|
        Chords.midi_notes(names, search:).each_with_index do |notes, i|
          chord = Chords.parse(names[i])
          missing = required_pcs(chord) - notes.map { |n| n % 12 }
          assert_empty missing, "progression #{index} #{names[i]} (search #{search}) lost pitch classes #{missing}"
          assert notes.size <= [Chords::MAX_VOICES, 1 + required_pcs(chord).uniq.size].max, "progression #{index} #{names[i]} has #{notes.size} voices"
        end
      end
    end
  end

  def test_a_slash_chord_keeps_its_root_when_the_bass_is_another_note
    notes = Chords.voice("Dbmaj7/Eb")
    assert_equal 3, notes.first % 12
    assert_equal [0, 1, 5, 8], notes.drop(1).map { |n| n % 12 }.uniq.sort, "Db F Ab C all sound over the Eb bass"
  end

  def test_slash_chords_put_the_bass_note_in_the_low_octave
    notes = Chords.voice("Db/E")
    assert_equal 4, notes.first % 12
    assert_equal [1, 5, 8], notes.drop(1).map { |n| n % 12 }.sort
  end

  def test_over_the_voice_cap_the_fifth_goes_and_the_third_seventh_and_extension_stay
    chord = Chords.parse("C13")
    assert_equal [4, 10, 2, 9], Chords.upper_pcs(chord).sort_by { |pc| [4, 10, 2, 9].index(pc) }
    refute_includes Chords.upper_pcs(chord), 7
    assert_includes Chords.upper_pcs(Chords.parse("C7b5")), 6, "an altered fifth stays when the chord fits"
  end

  def test_voice_leading_moves_each_chord_close_to_the_last
    centres = Chords.midi_notes(%w[Cm9 Fm9 Bbm9 Ebmaj9]).map { |n| n.drop(1).sum / (n.size - 1) }
    centres.each_cons(2) { |a, b| assert_operator (a - b).abs, :<=, 7 }
  end

  # The top line's leaps over a major third, as a share of all chord changes in all progressions.
  def top_leap_share(search)
    leaps = 0
    changes = 0
    PROGRESSIONS.each do |names|
      Chords.midi_notes(names, search:).each_cons(2) do |a, b|
        changes += 1
        leaps += 1 if (a.max - b.max).abs > 4
      end
    end
    leaps.to_f / changes
  end

  def mean_movement(search)
    total = 0.0
    count = 0
    PROGRESSIONS.each do |names|
      Chords.midi_notes(names, search:).each_cons(2) do |a, b|
        b.drop(1).each do |n|
          total += a.drop(1).map { |m| (n - m).abs }.min
          count += 1
        end
      end
    end
    total / count
  end

  # (b) The search keeps the top line smooth, and switching it off gives a measurably larger share.
  def test_the_search_keeps_top_line_leaps_under_sixteen_percent_and_the_switch_shows_it
    with = top_leap_share(true)
    without = top_leap_share(false)
    assert_operator with, :<, 0.16
    assert_operator without, :>, with + 0.05, "plain nearest-tone voicing leaps #{without}, searched #{with}"
  end

  # (c) Same names, same notes, every time; the command's switch changes the render.
  def test_voicing_is_deterministic
    names = PROGRESSIONS.fetch(7)
    assert_equal Chords.midi_notes(names), Chords.midi_notes(names)
    assert_equal Chords.freqs(names), Chords.freqs(names)
    refute_equal Chords.midi_notes(PROGRESSIONS.flatten.first(12)), Chords.midi_notes(PROGRESSIONS.flatten.first(12), search: false)
  end

  def test_no_voice_search_switch_changes_the_midi_file
    Dir.mktmpdir do |dir|
      args = ["--progression", "5", "--seed", "1"]
      run_dilla(*args, "--midi", File.join(dir, "a.mid"), "--out", File.join(dir, "a.wav"), chdir: dir)
      run_dilla(*args, "--no-voice-search", "--midi", File.join(dir, "b.mid"), "--out", File.join(dir, "b.wav"), chdir: dir)
      refute_equal File.binread(File.join(dir, "a.mid")), File.binread(File.join(dir, "b.mid"))
    end
  end

  # ------------------------------------------------------------- profiles and patterns

  def test_every_pattern_is_rows_of_sixteen_steps
    DATA.fetch("drum_patterns").each do |id, pattern|
      rows = pattern.select { |k, v| v.is_a?(Array) && !%w[variants layers].include?(k) }
      assert_empty %w[hat kick] - rows.keys, id
      assert_empty rows.keys - %w[kick snare clap hat open rim tom perc], id
      size = pattern.fetch("steps", 16)
      assert_includes [16, 32], size, id
      rows.each_value do |row|
        assert_equal size, row.size, id
        assert(row.all? { |c| c.is_a?(Array) ? c[0].between?(0, 1) : c.between?(0, 1) }, id)
      end
    end
  end

  def test_the_inversion_pattern_has_no_kick_on_one
    inversion = DATA.fetch("drum_patterns").fetch("offbeat_inversion")
    on = ->(row) { inversion[row].each_index.select { |i| inversion[row][i] == 1 } }
    assert_equal [7, 12], on.("kick")
    assert_equal [4, 12], on.("snare")
    assert_equal [2, 6, 10, 14], on.("hat")
  end

  def test_dilla_pattern_keeps_fast_accented_hats_and_quiet_ghost_hits
    pattern = DATA.fetch("drum_patterns").fetch("dilla_shadow")
    assert_equal %w[hat kick snare], pattern.keys.sort, "the legacy pattern stays safe without a kit"
    assert_equal %w[hat kick snare], DATA.fetch("drum_patterns").fetch("dilla_broken").keys.sort
    assert_equal 16, pattern.fetch("hat").size
    assert(pattern.fetch("hat").all? { |velocity| velocity.to_f.positive? })
    assert_operator pattern.fetch("hat").uniq.size, :>, 2
    assert_includes pattern.fetch("kick"), 0.72
    assert_includes pattern.fetch("kick"), 0.56
    assert_includes pattern.fetch("snare"), 0.28

    hits = sequencer("dilla_shadow", seed: 7).drum_hits("dilla_shadow", 92.0, 60.0 / 92 * 4)
    ghost = hits.find { |role, _, strength| role == "snare" && strength == 0.28 }
    refute_nil ghost
    assert_equal 3, ghost.size
  end

  def test_every_profile_offset_is_inside_the_window
    DATA.fetch("groove_profiles").each do |id, profile|
      (profile["offsets"] || {}).each_value { |v| assert_operator v.abs, :<=, MAX_OFFSET, id }
      assert_operator profile.fetch("pd_amount", 1.0), :<=, 1.5, id
      assert_operator (profile["sidechain"] || {}).fetch("amount", 0.0), :<=, 1.0, id
    end
  end

  def test_the_sidechain_is_off_unless_a_profile_asks
    assert_equal %w[pump techno_arp industrial_arp], DATA.fetch("groove_profiles").select { |_, p| p.key?("sidechain") }.keys
  end

  # ------------------------------------------------------------- timing

  def test_the_pattern_loops_across_the_whole_progression
    bar = 60.0 / 88 * 4
    hits = sequencer("dry").drum_hits("boom_bap", 88.0, bar * 6)
    assert_equal [0, 1, 2, 3, 4, 5], hits.map { |_, t| (t / bar).floor }.uniq.sort
    assert_equal 12, hits.count { |role, _| role == "snare" }
  end

  def test_pd_amount_zero_is_the_grid
    step = 60.0 / 88 / 4
    hits = sequencer("early_snare_late_hats", pd_amount: 0.0).drum_hits("syncopated_swing", 88.0, 8.0)
    hits.each { |_, t| assert_in_delta 0.0, (t / step) - (t / step).round, 1e-6 }
  end

  def test_the_early_snare_late_kick_direction_and_the_window
    step = 60.0 / 88 / 4
    hits = sequencer("early_snare_late_hats").drum_hits("syncopated_swing", 88.0, 40.0)
    snare = offsets_from_grid(hits, "snare", step)
    kick = offsets_from_grid(hits, "kick", step)
    assert_operator snare.sum / snare.size, :<, 0, "the snare sits early"
    assert_operator kick.sum / kick.size, :>, 0, "the kicks sit late"
    assert((snare + kick + offsets_from_grid(hits, "hat", step)).all? { |o| o.abs <= MAX_OFFSET + 1e-9 }, "swing and offset together stay in the window")
  end

  def test_the_first_kick_takes_its_own_offset
    hits = sequencer("early_snare_late_hats").drum_hits("syncopated_swing", 88.0, 12.0)
    assert_in_delta 0.0, hits.find { |r, _| r == "kick" }[1], 1e-9
    later = hits.select { |r, _| r == "kick" }[1]
    refute_in_delta 0.0, later[1] % (60.0 / 88 / 4), 1e-4
  end

  def test_pd_amount_scales_the_pull_from_the_grid
    step = 60.0 / 88 / 4
    mean = lambda do |amount|
      hits = sequencer("behind_the_beat", pd_amount: amount, seed: 3).drum_hits("boom_bap", 88.0, 20.0)
      offs = offsets_from_grid(hits, "snare", step).map(&:abs)
      offs.sum / offs.size
    end
    assert_operator mean.call(1.5), :>, mean.call(1.0)
    assert_operator mean.call(1.0), :>, mean.call(0.5)
    assert_equal 1.5, sequencer("dry", pd_amount: 9.0).pd_amount
  end

  def test_drunk_sixteenths_are_seeded_and_never_past_the_window
    a = sequencer("dry", seed: 11).drum_hits("drunk_16ths", 88.0, 20.0)
    assert_equal a, sequencer("dry", seed: 11).drum_hits("drunk_16ths", 88.0, 20.0)
    refute_equal a, sequencer("dry", seed: 12).drum_hits("drunk_16ths", 88.0, 20.0)
    step = 60.0 / 88 / 4
    assert(a.all? { |_, t| (t - ((t / step).round * step)).abs <= MAX_OFFSET + 1e-9 })
    assert_operator a.count { |r, _| r == "hat" }, :>, 100, "all sixteenths hit"
  end

  def test_swing_is_per_role_and_takes_the_off_beat_eighths
    data = JSON.parse(JSON.generate(DATA))
    data["groove_profiles"]["probe"] = { "drum_swing" => { "hat" => 0.55, "kick" => 0.5 } }
    step = 60.0 / 88 / 4
    hits = sequencer("probe", data:).drum_hits("boom_bap", 88.0, 8.0)
    assert(offsets_from_grid(hits, "kick", step).all? { |o| o.abs < 1e-9 }, "the kick stays on the grid")
    late = hits.select { |r, t| r == "hat" && ((t / step).round % 4) == 2 }.map { |_, t| t - ((t / step).round * step) }
    refute_empty late
    late.each { |o| assert_in_delta 0.05 * 2 * 2 * step, o, 1e-4 }
  end

  # ------------------------------------------------------------- the pocket

  POCKET = "straight_hats_snare_ahead"

  def lean_steps(hits, role, bpm)
    step = 60.0 / bpm / 4
    offsets_from_grid(hits, role, step).map { |o| o / step }
  end

  def test_the_pocket_is_the_default_profile_and_the_random_one
    assert_equal POCKET, DATA.fetch("default_profile")
    assert_includes DATA.fetch("groove_profiles"), POCKET
    Dir.mktmpdir do |dir|
      %w[--progression\ 2 --random].each_with_index do |flag, index|
        output = File.join(dir, "take-#{index}.wav")
        _o, err, status = run_dilla(*flag.split, "--drums", "boom_bap", "--seed", "4", "--out", output, chdir: dir)
        assert status.success?, err
        assert_match(/profile=#{POCKET}/, _o)
        assert File.file?(output)
      end
    end
  end

  def test_the_hats_hold_the_grid_the_snare_leads_and_the_kick_lags_after_its_anchor
    hits = sequencer(POCKET).drum_hits("syncopated_swing", 128.0, 60.0)
    assert(lean_steps(hits, "hat", 128.0).all? { |l| l.abs < 1e-6 }, "the hats hold the grid")
    backbeats = sequencer(POCKET).drum_hits("boom_bap", 128.0, 60.0)
    snare = lean_steps(backbeats, "snare", 128.0)
    refute_empty snare
    assert_operator snare.sum / snare.size, :<, -0.2
    kick = hits.select { |r, _| r == "kick" }
    anchors = kick.select { |_, t| ((t / (60.0 / 128 / 4)).round % 16).zero? }
    others = kick - anchors
    assert(anchors.all? { |_, t| (t / (60.0 / 128 / 4) - (t / (60.0 / 128 / 4)).round).abs < 1e-6 }, "the downbeat kick holds")
    assert(others.all? { |_, t| (t / (60.0 / 128 / 4) - (t / (60.0 / 128 / 4)).round) > 0.05 }, "the other kicks lag")
  end

  def test_ghost_snares_lag_further_than_the_kick
    hits = sequencer(POCKET).drum_hits("syncopated_swing", 128.0, 60.0)
    step = 60.0 / 128 / 4
    ghosts = hits.select { |r, t| r == "snare" && ![4, 12].include?((t / step).round % 16) }
    refute_empty ghosts
    ghost_lean = ghosts.map { |_, t| t / step - (t / step).round }
    kick_lean = hits.select { |r, t| r == "kick" && ((t / step).round % 16).positive? }.map { |_, t| t / step - (t / step).round }
    assert_operator ghost_lean.sum / ghost_lean.size, :>, kick_lean.sum / kick_lean.size
  end

  def test_every_bar_leans_as_the_first_did_and_the_seed_alone_changes_the_drift
    bar = 60.0 / 100 * 4
    hits = sequencer(POCKET, seed: 9).drum_hits("broken_beat", 100.0, bar * 4)
    first = hits.select { |_, t| t < bar }.sort
    (1..3).each do |n|
      again = hits.select { |_, t| t >= n * bar && t < (n + 1) * bar }.map { |r, t| [r, t - n * bar] }.sort
      assert_equal first.size, again.size
      first.zip(again).each { |(r, a), (r2, b)| assert_equal r, r2; assert_in_delta a, b, 1e-9 }
    end
    other = sequencer(POCKET, seed: 10).drum_hits("broken_beat", 100.0, bar * 4)
    refute_equal hits, other
  end

  # A player's hand does not repeat; a profile without bar_drift_steps does, as its first bar did.
  def test_bar_drift_makes_bars_differ_inside_the_window
    hits = four_bars("dilla_shadow")

    refute_equal times_in_bar(hits, 0, role: "snare"), times_in_bar(hits, 1, role: "snare")
    assert(offsets_from_grid(hits, "snare", 60.0 / 82 / 4).all? { |offset| offset.abs <= MAX_OFFSET + 1e-9 })
  end

  def test_a_profile_without_bar_drift_repeats_its_first_bar
    plain = four_bars(POCKET)

    assert_equal times_in_bar(plain, 0), times_in_bar(plain, 1)
  end

  def test_chords_lean_behind_the_beat_only_when_the_profile_says_so
    shadow = sequencer("dilla_shadow", seed: 3)
    leans = (0..7).map { |index| shadow.chord_lean(index, 60.0 / 82) }

    assert_operator leans.sum / leans.size, :>, 0.0
    assert_operator leans.uniq.size, :>, 1, "each chord leans a little differently"
    assert(leans.all? { |lean| lean.abs <= MAX_OFFSET + 1e-9 })
    assert_equal 0.0, sequencer(POCKET, seed: 3).chord_lean(2, 60.0 / 82)
  end

  def bar_seconds = 60.0 / 82 * 4

  def four_bars(profile) = sequencer(profile, seed: 5).drum_hits("dusty_laid_back", 82.0, bar_seconds * 4)

  def times_in_bar(hits, number, role: nil)
    inside = hits.select do |hit|
      (role.nil? || hit.first == role) && hit.last >= number * bar_seconds && hit.last < (number + 1) * bar_seconds
    end
    inside.map { |hit| (hit.last - (number * bar_seconds)).round(6) }
  end

  # The same share of a sixteenth is a different number of milliseconds at each tempo.
  def test_the_same_share_gives_different_milliseconds_at_70_88_and_104_bpm
    ms = [70.0, 88.0, 104.0].map do |bpm|
      hits = sequencer(POCKET, seed: 1).drum_hits("boom_bap", bpm, 60.0 / bpm * 8)
      step = 60.0 / bpm / 4
      later = hits.select { |r, t| r == "kick" && t > step }.first[1]
      [(later - (later / step).round * step) * 1000, (later - (later / step).round * step) / step]
    end
    shares = ms.map(&:last)
    assert_in_delta shares[0], shares[1], 1e-6, "the share is one number"
    assert_in_delta shares[1], shares[2], 1e-6
    assert_operator ms[0].first, :>, ms[1].first
    assert_operator ms[1].first, :>, ms[2].first
  end

  def test_the_pocket_never_moves_a_hit_past_the_window_and_groove_scales_it
    [50.0, 70.0, 88.0, 104.0, 140.0].each do |bpm|
      hits = sequencer(POCKET).drum_hits("syncopated_swing", bpm, 60.0)
      step = 60.0 / bpm / 4
      assert(%w[kick snare hat].all? { |role| offsets_from_grid(hits, role, step).all? { |o| o.abs <= MAX_OFFSET + 1e-9 } }, bpm.to_s)
    end
    half = lean_steps(sequencer(POCKET, pd_amount: 0.5).drum_hits("boom_bap", 140.0, 30.0), "snare", 140.0)
    full = lean_steps(sequencer(POCKET, pd_amount: 1.0).drum_hits("boom_bap", 140.0, 30.0), "snare", 140.0)
    assert_operator full.sum / full.size, :<, half.sum / half.size
    grid = sequencer(POCKET, pd_amount: 0.0).drum_hits("syncopated_swing", 88.0, 8.0)
    assert(lean_steps(grid, "kick", 88.0).all? { |l| l.abs < 1e-6 })
  end

  def test_every_pocket_role_is_a_pattern_role_with_leans_in_steps
    pocket = DATA.fetch("groove_profiles").fetch(POCKET).fetch("pocket")
    roles = pocket.keys - %w[backbeat ghost]
    assert_equal %w[hat kick snare], roles.sort
    pocket.each_value { |s| next unless s.is_a?(Hash); assert_operator s.fetch("shift_steps", 0.0).abs + s.fetch("drift_steps", 0.0), :<, 1.0 }
  end

  def test_a_role_the_pocket_does_not_own_keeps_its_offsets
    data = JSON.parse(JSON.generate(DATA))
    data["groove_profiles"]["probe"] = { "pocket" => { "kick" => { "shift_steps" => 0.1 } }, "offsets" => { "hat" => 0.01 } }
    hits = sequencer("probe", data:).drum_hits("boom_bap", 88.0, 8.0)
    step = 60.0 / 88 / 4
    assert(offsets_from_grid(hits, "hat", step).all? { |o| (o - 0.01).abs < 1e-9 })
  end

  # ------------------------------------------------------------- arp and echo

  def test_each_arp_pattern_orders_the_voices_and_fills_the_chord
    pool = [40, 52, 60, 67]
    assert_equal [40, 52, 60, 67, 40, 52, 60, 67], Arp.sequence("up", pool, 8, 1)
    assert_equal [67, 60, 52, 40, 67, 60, 52, 40], Arp.sequence("down", pool, 8, 1)
    assert_equal [40, 52, 60, 67, 60, 52, 40, 52], Arp.sequence("updown", pool, 8, 1)
    assert_equal [40, 67, 52, 60, 40, 67, 52, 60], Arp.sequence("converge", pool, 8, 1)
    random = Arp.sequence("random_seeded", pool, 8, 3)
    assert_equal random, Arp.sequence("random_seeded", pool, 8, 3)
    refute_equal random, Arp.sequence("random_seeded", pool, 8, 4)
    assert_equal 8, random.size
    assert(random.all? { |n| pool.include?(n) })
    assert_equal [40, 52, 64], Arp.pool([40, 52], 2)
    assert_raises(ArgumentError) { Arp.sequence("sideways", pool, 4, 1) }
  end

  def test_the_arp_plays_one_note_per_rate_and_each_chord_fills_its_bars
    seq = sequencer("arp_echo_soft")
    arp = seq.arp_settings(nil)
    assert_equal "up", arp["pattern"]
    assert_equal 4.0, arp["rate"]
    buf = seq.render_arp(%w[Cm9 Fm9], 120.0, 4.0, arp.merge("octaves" => 1))
    assert_in_delta 2 * 2.0 + 1.0, buf.size / SAMPLE_RATE.to_f, 0.01
    refute(buf.first(2000).all?(&:zero?), "the first note sounds on the downbeat")
    assert_operator buf.map(&:abs).max, :<=, 1.0
  end

  def test_the_arp_flag_chooses_the_pattern_and_unknown_ones_are_refused
    assert_equal "down", sequencer("dry").arp_settings("down")["pattern"]
    assert_nil sequencer("dry").arp_settings(nil)
    assert_equal "updown", sequencer("dry").arp_settings(true)["pattern"]
  end

  def impulse(length, at = 0)
    Array.new(length, 0.0).tap { |b| b[at] = 1.0 }
  end

  def test_the_echo_has_three_taps_at_one_two_and_three_times_the_delay
    delay = 0.05
    d = (delay * SAMPLE_RATE).round
    out = Echo.process(impulse(d * 4), delay:, heads: [1, 2, 3], intensity: 0.0, volume: 1.0, lowpass: nil, saturation: 0.0)
    assert_in_delta 1.0, out[0], 1e-9, "the dry sound stays"
    taps = [1, 2, 3].map { |h| out[h * d] }
    assert(taps.all? { |v| v > 0.2 }, "a tap at each head: #{taps}")
    assert_in_delta 0.0, out[d / 2], 1e-9
    assert_in_delta 0.0, out[(2.5 * d).to_i], 1e-9
    only = Echo.process(impulse(d * 4), delay:, heads: [2], intensity: 0.0, volume: 1.0, lowpass: nil, saturation: 0.0)
    assert_operator only[2 * d], :>, 0.2
    assert_in_delta 0.0, only[d], 1e-9
  end

  def test_each_repeat_is_quieter_and_the_tail_is_darker
    delay = 0.05
    d = (delay * SAMPLE_RATE).round
    out = Echo.process(impulse(d * 8), delay:, heads: [1], intensity: 0.6, volume: 1.0, lowpass: 3000, saturation: 0.3)
    peaks = (1..5).map { |k| out[k * d] }
    peaks.each_cons(2) { |a, b| assert_operator b, :<, a }
    assert_operator peaks.first, :>, 0.05
    # darker: the lowpass spreads a repeat into the samples after it
    assert_operator out[d + 3], :>, 0.0
  end

  def test_dub_echo_and_crystallizer_create_finite_non_reverb_tails
    input = Array.new(SAMPLE_RATE / 3) do |i|
      0.22 * Math.sin(2.0 * Math::PI * 80.0 * i / SAMPLE_RATE) +
        0.08 * Math.sin(2.0 * Math::PI * 2400.0 * i / SAMPLE_RATE)
    end
    dub = FX.dub_echo(input, {
      "delay_ms" => 120, "heads" => [1, 2, 3], "intensity" => 0.65,
      "volume" => 0.72, "lowpass" => 4200, "saturation" => 0.9,
      "reverb" => 0.0, "tail" => 0.2
    })
    assert_equal input.size + (0.2 * SAMPLE_RATE).to_i, dub.size
    assert(dub.all?(&:finite?))
    refute_equal input, dub

    crystal = FX.crystallizer(input, {
      "delay_ms" => 90, "semitones" => 12, "feedback" => 0.4,
      "mix" => 0.5, "repeats" => 3, "tail" => 0.3, "grain_ms" => 60
    })
    assert_operator crystal.size, :>, input.size
    assert(crystal.all?(&:finite?))
    refute_equal input, crystal
    assert_operator crystal.map(&:abs).max, :<, 1.0
    assert_same input, FX.crystallizer(input, nil)
  end

  def test_the_echo_is_stable_at_the_top_intensity_and_silence_stays_silent
    rng = Random.new(1)
    loud = Array.new(SAMPLE_RATE) { (rng.rand * 2) - 1 }
    out = Echo.process(loud, delay: 0.03, heads: [1, 2, 3], intensity: 5.0, volume: 1.0, lowpass: 4000, saturation: 1.0)
    assert(out.all?(&:finite?))
    assert_operator out.map(&:abs).max, :<, 6.0
    assert_in_delta 0.0, out.last(2000).map(&:abs).max, 0.5, "the tail dies away"
    silent = Echo.process(Array.new(5000, 0.0), delay: 0.01, heads: [1, 2], intensity: 0.9, volume: 1.0, lowpass: 3000, saturation: 0.5, reverb: 0.2)
    assert(silent.all?(&:zero?))
  end

  def test_echo_flags_choose_heads_and_refuse_unknown_modes
    seq = sequencer("dry")
    assert_nil seq.echo_settings
    assert_equal [1, 2, 3], seq.echo_settings(flag: "1,2,3")["heads"]
    assert_equal [1, 2], seq.echo_settings(flag: true)["heads"]
    settings = seq.echo_settings(flag: true, mix: 0.3, feedback: 0.7, time_ms: 250.0)
    assert_equal [0.3, 0.7, 250.0], settings.values_at("echo_volume", "intensity", "time_ms")
    assert_equal [1, 2], sequencer("arp_echo_soft").echo_settings["heads"]
    assert_equal [[1, 2, 3], 0.75, 3], [sequencer("arp_echo").echo_settings["heads"], sequencer("arp_echo").echo_settings["intensity"], sequencer("arp_echo").arp_settings(nil)["rate"]]
  end

  def test_arp_and_echo_render_a_wav_and_the_plain_render_is_untouched_by_them
    Dir.mktmpdir do |dir|
      plain = File.join(dir, "p.wav")
      other = File.join(dir, "q.wav")
      arp = File.join(dir, "a.wav")
      run_dilla("--progression", "3", "--beats", "2", "--seed", "2", "--out", plain, chdir: dir)
      _o, err, status = run_dilla("--progression", "3", "--beats", "2", "--seed", "2", "--profile", "arp_echo", "--pad", "--out", arp, chdir: dir)
      assert status.success?, err
      run_dilla("--progression", "3", "--beats", "2", "--seed", "2", "--out", other, chdir: dir)
      assert_equal File.binread(plain), File.binread(other)
      assert_operator File.size(arp), :>, File.size(plain), "the echo tail makes it longer"
      assert_operator File.binread(arp).byteslice(44..).unpack("s<*").map(&:abs).max, :>, 1000
    end
  end

  # ------------------------------------------------------------- arp modifiers and strum

  def plucks(count = 8)
    Array.new(count) { |i| Pluck.new(i * 0.2, 0.0, 60 + i, 0.15, i.even? ? 1.0 : 0.5) }
  end

  def modify(name, params, count: 8, seed: 1)
    Arp.modify(plucks(count), name, params, Random.new(seed), slot: 0.2, peak: 1.0)
  end

  def test_euclidean_keeps_the_pulses_of_the_steps
    kept = modify("euclidean", { "steps" => 8, "pulses" => 5 })
    assert_equal 5, kept.size
    assert_equal 8, modify("euclidean", { "steps" => 8, "pulses" => 8 }).size
    assert_equal 6, modify("euclidean", { "steps" => 8, "pulses" => 3 }, count: 16).size
  end

  def test_probability_drops_notes_by_seed
    assert_equal 8, modify("probability", { "probability" => 1.0 }).size
    assert_empty modify("probability", { "probability" => 0.0 })
    some = modify("probability", { "probability" => 0.5 }, count: 200)
    assert some.size.between?(70, 130), some.size.to_s
    assert_equal some.map(&:midi), modify("probability", { "probability" => 0.5 }, count: 200).map(&:midi)
  end

  def test_note_repeat_splits_each_note_and_each_repeat_is_six_percent_quieter
    out = modify("note_repeat", { "count" => 3 }, count: 2)
    assert_equal 6, out.size
    assert_in_delta 0.2 / 3, out[1].base - out[0].base, 1e-9
    assert_in_delta 0.94, out[1].gain / out[0].gain, 1e-9
    assert_equal 8, modify("note_repeat", { "count" => 1 }).size
    assert_equal 6, modify("note_repeat", { "count" => 99 }, count: 1).size
  end

  def test_ratchet_only_splits_accented_notes_into_at_most_the_maximum
    out = modify("ratchet", { "max" => 3, "chance" => 1.0 })
    accented = out.select { |p| p.gain >= 0.99 }
    assert_operator out.size, :>, 8
    assert_operator out.size, :<=, 4 * 3 + 4
    assert_equal 4, out.count { |p| p.gain == 0.5 }, "the soft notes stay whole"
    assert_operator accented.size, :>=, 4
    assert_equal 8, modify("ratchet", { "max" => 3, "chance" => 0.0 }).size
  end

  def test_humanize_moves_time_and_gain_a_little_and_the_clamp_holds
    out = modify("humanize", { "ms" => 4.0, "gain" => 0.06 }, count: 50)
    assert(out.all? { |p| p.off.abs <= 0.004 + 1e-9 })
    assert(out.any? { |p| p.off.abs > 1e-5 })
    assert(out.all? { |p| p.gain.between?(0.0, 1.0) })
    Dir.mktmpdir do |dir|
      data = JSON.parse(JSON.generate(DATA))
      data["arp"].merge!("modifiers" => ["humanize"], "humanize" => { "ms" => 500.0, "gain" => 0.0 })
      seq = sequencer("dry", data:)
      buf = seq.render_arp(%w[Cm9], 120.0, 4.0, seq.arp_settings(true))
      assert_operator buf.size, :>, 0
    end
  end

  def test_grace_notes_come_before_the_note_and_softer
    out = modify("grace", { "tones" => [57, 58, 60], "gain" => 0.3 }, count: 2)
    assert_equal 4, out.size
    assert_equal [58, 60], out.first(2).map(&:midi), "the next chord tone below, not a chromatic neighbour"
    assert_operator out[0].base, :<, out[1].base
    assert_in_delta 0.3, out[0].gain, 1e-9
  end

  def test_an_unknown_modifier_is_refused_and_modifiers_chain_in_order
    assert_raises(ArgumentError) { modify("sideways", {}) }
    seq = sequencer("arp_fast")
    arp = seq.arp_settings(nil)
    assert_equal %w[ratchet probability humanize], arp["modifiers"]
    a = seq.render_arp(%w[Cm9], 150.0, 2.0, arp)
    assert_equal a, seq.render_arp(%w[Cm9], 150.0, 2.0, arp)
  end

  def test_strum_staggers_the_voices_lowest_first
    flat = Synth.chord([220.0, 330.0], 0.5)
    strummed = Synth.chord([220.0, 330.0], 0.5, strum: 0.02)
    assert_equal flat.size, strummed.size
    refute_equal flat, strummed
    assert_in_delta 0.018, sequencer("dry").strum(true), 1e-9
    assert_equal 0.0, sequencer("dry").strum(nil)
    assert_in_delta 0.03, sequencer("dry").strum(30.0), 1e-9
  end

  # ------------------------------------------------------------- endless play

  def fake_player(dir)
    sink = File.join(dir, "heard.pcm")
    script = File.join(dir, "fake.sh")
    File.write(script, "#!/bin/sh\ncat > #{sink}\n")
    File.chmod(0o755, script)
    ["sh #{script}", sink]
  end

  def test_play_streams_passes_into_the_player_and_never_repeats_the_last_progression
    Dir.mktmpdir do |dir|
      player, sink = fake_player(dir)
      out, err, status = run_dilla("--play", "--player", player, "--passes", "4", "--beats", "1", "--seed", "8",
                                   "--profile", "dry", "--mode", "pad", "--tape", "0", "--decks", "1", "--out", File.join(dir, "x.wav"), chdir: dir)
      assert status.success?, err
      passes = out.scan(/^pass (\d+): progression (\d+) \(/)
      assert_equal %w[1 2 3 4], passes.map(&:first)
      indices = passes.map { |_, i| i.to_i }
      indices.each_cons(2) { |a, b| refute_equal a, b }
      assert_operator File.size(sink), :>, 4 * 44_100 * 2, "raw 16-bit mono PCM reached the player"
      assert_equal 0, File.size(sink) % 2
    end
  end

  def test_the_echo_tail_rings_on_after_the_last_note
    settings = sequencer("arp_echo").echo_settings
    assert_equal [1, 2, 3], settings["heads"]
    assert_operator settings["echo_volume"], :>=, 0.65
    assert_operator settings["tail"], :>=, 10
    assert_equal 78.0, sequencer("arp_echo").bpm
    assert_equal 88.0, sequencer("dry").bpm
    out = Echo.process(impulse(100), delay: 0.05, heads: [1], intensity: 0.85, volume: 1.0, lowpass: nil, saturation: 0.0, tail: 3.0)
    assert_equal 100 + (3 * SAMPLE_RATE), out.size
    assert_operator out.last(2205).map(&:abs).max, :<, out[2205, 2205].map(&:abs).max, "the tail dies away"
  end

  # ------------------------------------------------------------- voices, colour, mix

  def test_every_voice_makes_finite_audible_samples_and_drops_notes_past_the_limit
    DATA.fetch("voices").each do |name, spec|
      next if spec["family"] == "fluid" # a soundfont voice is mixed by the sequencer, never note by note

      samples = Voices.note(spec, 57, 0.2, 0.2)
      assert_operator samples.size, :>, 1000, name
      assert(samples.all?(&:finite?), name)
      assert_operator samples.map(&:abs).max, :>, 0.01, name
      assert_empty Voices.note(spec, 57 + 120, 0.2, 0.2), "#{name}: above the limit, nothing sounds"
    end
    assert(Synth.note(Chords.hz(150), 0.1).all?(&:zero?), "a sine stack past the limit is silent, not folded down")
  end

  def test_transpose_moves_notes_and_wrap_folds_them_under_the_audible_top
    plain = Chords.midi_notes(%w[Cm9 Fm9])
    assert_equal plain.map { |c| c.map { |n| n + 12 } }, Chords.midi_notes(%w[Cm9 Fm9], transpose: 12)
    high = Chords.midi_notes(%w[Cm9 Fm9], transpose: 144).flatten
    assert(high.none? { |n| Voices.audible?(Chords.hz(n)) }, "twelve octaves up is past Nyquist")
    folded = Chords.midi_notes(%w[Cm9 Fm9], transpose: 144, wrap: true).flatten
    assert(folded.all? { |n| Chords.hz(n) <= AUDIBLE_TOP_HZ })
    assert_equal plain.flatten.map { |n| n % 12 }, folded.map { |n| n % 12 }, "folding keeps the pitch classes"
  end

  def test_a_transpose_past_nyquist_warns_and_renders_silence
    Dir.mktmpdir do |dir|
      out = File.join(dir, "x.wav")
      _o, err, status = run_dilla("--progression", "9", "--beats", "1", "--octaves", "12", "--mode", "pad", "--no-master", "--out", out, chdir: dir)
      assert status.success?, err
      assert_match(/warning: \d+ of \d+ notes are above/, err)
      assert File.binread(out).byteslice(44..).unpack("s<*").all?(&:zero?)
    end
  end

  def noise(count = 20_000)
    rng = Random.new(2)
    Array.new(count) { (rng.rand * 2) - 1 }
  end

  def tone_energy(buf, hz)
    re = im = 0.0
    buf.each_with_index do |v, i|
      angle = 2 * Math::PI * hz * i / SAMPLE_RATE
      re += v * Math.cos(angle)
      im += v * Math.sin(angle)
    end
    Math.sqrt((re * re) + (im * im)) / buf.size
  end

  def test_sonitex_reduces_bit_depth_limits_the_band_and_drives_harmonics_within_a_safe_peak
    levels = Colour.crush(noise, 4, 1.0).uniq.size
    assert_operator levels, :<=, 2**4 + 1
    preset = DATA.dig("sonitex", "presets", "heavy")
    high = noise.then { |n| tone_energy(Colour.highpass(n, 9000.0), 12_000) }
    out = Colour.sonitex(noise, preset, 1, 1)
    assert_operator tone_energy(out, 12_000), :<, tone_energy(noise, 12_000) * 0.2, "energy above the cutoff drops"
    assert_operator high, :>, 0
    sine = Array.new(20_000) { |i| 0.3 * Math.sin(2 * Math::PI * 440 * i / SAMPLE_RATE) }
    driven = Colour.sonitex(sine, DATA.dig("sonitex", "presets", "classic"), 1, 1)
    assert_operator tone_energy(driven, 1320) / tone_energy(driven, 440), :>, 3 * tone_energy(sine, 1320) / tone_energy(sine, 440) + 0.001
    assert_operator Colour.sonitex(noise, preset, 3, 1).map(&:abs).max, :<, 1.0
  end

  def test_the_summing_colour_is_stable_and_never_much_louder_and_off_changes_nothing
    rms = ->(b) { Math.sqrt(b.sum { |v| v * v } / b.size) }
    loud = noise.map { |v| v * 0.9 }
    [0.2, 0.5, 1.0].each do |amount|
      out = Colour.vcs(loud, amount)
      assert(out.all?(&:finite?))
      assert_operator 20 * Math.log10(rms.call(out) / rms.call(loud)), :<=, 3.0
    end
    assert_same loud, Colour.vcs(loud, 0.0)
    assert_same loud, sequencer("dry").colour(loud, nil, 0.0)
  end

  def test_colour_is_off_by_default_and_the_bytes_say_so
    Dir.mktmpdir do |dir|
      a = File.join(dir, "a.wav")
      b = File.join(dir, "b.wav")
      c = File.join(dir, "c.wav")
      base = ["--progression", "2", "--beats", "1", "--mode", "pad", "--seed", "4"]
      run_dilla(*base, "--out", a, chdir: dir)
      run_dilla(*base, "--vcs", "0", "--out", b, chdir: dir)
      _o, err, status = run_dilla(*base, "--sonitex", "heavy", "--sonitex-instances", "3", "--vcs", "0.5", "--out", c, chdir: dir)
      assert status.success?, err
      assert_equal File.binread(a), File.binread(b)
      refute_equal File.binread(a), File.binread(c)
    end
  end

  def test_a_chord_repeat_strikes_every_voice_on_every_mark_of_the_style
    seq = sequencer("chord_repeat")
    comp = seq.comp_settings(true).merge("pattern" => "x...x...x...x...", "modifiers" => [])
    seq_notes = Chords.midi_notes(%w[Cm9]).first.size
    assert_operator seq_notes, :>=, 4
    struck = 0
    plucks = []
    singles = seq.render_repeat(%w[Cm9], 120.0, 4.0, comp)
    refute(singles.all?(&:zero?))
    assert_includes DATA.dig("comp", "styles"), "dotted_eighth_push"
    DATA.dig("comp", "styles").each_value { |s| assert_equal 16, s["pattern"].size }
    assert_equal %w[chord_repeat dub_dark tape_dust], DATA.fetch("groove_profiles").select { |_, p| p.key?("repeat") }.keys
    assert_equal 0, struck + plucks.size
  end

  def test_mix_defaults_raise_the_kick_and_snare_and_drop_the_chords
    levels = sequencer("dry").mix(nil)
    assert_equal [6.0, 10.0, 10.0, 0.0, -3.0], levels.values_at("kick", "snare", "clap", "hat", "chords")
    assert_equal 3.0, sequencer("dry").mix("kick" => 3.0)["kick"]
  end

  def test_drums_only_kick_and_snare_rms_rise_by_the_stated_decibels_and_nothing_clips
    seq = sequencer("dry")
    rms = ->(b) { Math.sqrt(b.sum { |v| v * v } / b.size) }
    [["kick", 6.0], ["snare", 10.0]].each do |role, db|
      silent = Array.new(SAMPLE_RATE, 0.0)
      hits = [[role, 0.1], [role, 0.5]]
      before = seq.overlay_drums(silent, hits, { role => 0.0 })
      after = seq.overlay_drums(silent, hits, { role => db })
      rise = 20 * Math.log10(rms.call(after) / rms.call(before))
      assert_operator rise, :>=, db - 3.0, "#{role}: the soft limiter bends the loudest samples, so the rise falls a little short"
      assert_operator rise, :<=, db + 0.5, role
      assert_operator after.map(&:abs).max, :<=, 1.0
    end
    loud = seq.overlay_drums(Array.new(SAMPLE_RATE, 0.9), [["kick", 0.1], ["snare", 0.1]], { "kick" => 12.0, "snare" => 12.0 })
    assert_operator loud.map(&:abs).max, :<=, 1.0
  end

  def test_the_kick_is_added_after_the_duck
    seq = sequencer("pump")
    chords = Array.new(SAMPLE_RATE, 0.5)
    ducked = seq.duck(chords, [["kick", 0.1]])
    out = seq.overlay_drums(ducked, [["kick", 0.1]], { "kick" => 0.0 })
    start = (0.1 * SAMPLE_RATE).to_i
    assert_operator out[start + 200].abs, :>, ducked[start + 200].abs, "the kick sits on top of the pumped chords"
  end

  # ------------------------------------------------------------- the shuffle bags

  def test_every_progression_plays_once_per_cycle_and_nothing_repeats_back_to_back
    count = PROGRESSIONS.size
    list = Playlist.new(DATA, Random.new(5), {}, pool: "all")
    picks = Array.new(3 * count) { list.draw(profile: "dry") }
    seen = picks.map { |p| p[:prog] }
    assert_equal({ 3 => count }, seen.tally.values.tally)
    seen.each_cons(2) { |a, b| refute_equal a, b }
    families = picks.reject { |p| p[:mode] == "organ" }.map { |p| DATA.dig("voices", p[:voice], "group") } # the organ mode draws no patch
    families.each_cons(2) { |a, b| refute_equal a, b }
    picks.map { |p| p[:mode] }.each_cons(2) { |a, b| refute_equal a, b }
    picks.select { |p| p[:style] }.group_by { |p| p[:mode] }.each_value { |rows| rows.map { |p| p[:style] }.each_cons(2) { |a, b| refute_equal a, b } }
  end

  def test_one_bag_holds_every_patch_and_no_patch_or_family_repeats_inside_three_cycles
    names = PLAYABLE
    [1, 9, 40].each do |seed|
      list = Playlist.new(DATA, Random.new(seed))
      played = Array.new(3 * names.size) { list.draw(mode: "pad", profile: "dry")[:voice] }
      played.each_slice(names.size) { |cycle| assert_equal names.sort, cycle.sort, "every patch once before any comes back" }
      played.each_cons(2) do |a, b|
        refute_equal a, b
        refute_equal DATA.dig("voices", a, "group"), DATA.dig("voices", b, "group"), "#{a} then #{b}"
      end
    end
  end

  def test_the_patch_bag_is_saved_with_the_others_and_a_restart_goes_on_with_it
    first = Playlist.new(DATA, Random.new(3))
    a = Array.new(7) { first.draw(mode: "pad", profile: "dry")[:voice] }
    state = JSON.parse(JSON.generate(first.to_h))
    assert_includes state.keys, "voices"
    second = Playlist.new(DATA, Random.new(4), state)
    b = Array.new(PLAYABLE.size - 7) { second.draw(mode: "pad", profile: "dry")[:voice] }
    assert_equal PLAYABLE.sort, (a + b).sort
    refute_equal DATA.dig("voices", a.last, "group"), DATA.dig("voices", b.first, "group")
  end

  def test_a_fixed_voice_never_touches_the_bag
    list = Playlist.new(DATA, Random.new(2))
    assert_equal "rhodes_mark1", list.draw(voice: "rhodes_mark1", profile: "dry")[:voice]
    assert_nil list.to_h["voices"]
  end

  def test_patch_per_chord_draws_one_patch_for_each_chord_of_a_pad_from_the_same_bag
    list = Playlist.new(DATA, Random.new(6), {}, pool: "all")
    picks = Array.new(30) { list.draw(mode: "pad", profile: "dry", patch_per_chord: true) }
    picks.each { |pick| assert_equal PROGRESSIONS.fetch(pick[:prog]).size, pick[:voices].size }
    flat = picks.flat_map { |pick| pick[:voices] }
    names = PLAYABLE
    flat.each_slice(names.size).select { |cycle| cycle.size == names.size }.each { |cycle| assert_equal names.sort, cycle.sort }
    flat.each_cons(2) { |a, b| refute_equal DATA.dig("voices", a, "group"), DATA.dig("voices", b, "group") }
    assert_nil Playlist.new(DATA, Random.new(6)).draw(mode: "arp", profile: "dry", patch_per_chord: true)[:voices]
  end

  def test_a_pad_plays_its_voice_and_each_chord_of_a_morph_has_its_own
    seq = sequencer("dry")
    names = %w[Cmaj7 Fmaj7]
    plain = seq.render_chords(names, 120.0, 4.0)
    sine = seq.render_chords(names, 120.0, 4.0, voice: seq.voice_spec("sine"))
    assert_equal plain, sine, "the sine pad is the old pad"
    held = seq.render_chords(names, 120.0, 4.0, voice: seq.voice_spec("moog_pad"))
    refute_equal plain, held
    morph = seq.render_chords(names, 120.0, 4.0, voices: seq.voice_specs(%w[moog_pad rhodes_mark1]))
    chord = (4.0 * 0.5 * SAMPLE_RATE).to_i
    assert_equal held.first(chord - 2000), morph.first(chord - 2000), "the first chord keeps its patch"
    refute_equal held[chord + 5000, 8000], morph[chord + 5000, 8000], "and the second takes another"
  end

  def test_the_default_pool_is_the_essential_staples_and_every_index_exists
    essential = DATA.fetch("essential")
    assert_operator essential.size, :>=, 20
    assert(essential.all? { |i| i.between?(0, PROGRESSIONS.size - 1) })
    assert_equal essential.uniq, essential
    picks = Array.new(essential.size) { Playlist.new(DATA, Random.new(3)).draw(profile: "dry")[:prog] }
    assert(picks.all? { |i| essential.include?(i) })
    assert_operator PROGRESSIONS.size, :>, 300
  end

  def test_a_restart_goes_on_with_the_cycle
    first = Playlist.new(DATA, Random.new(1), {}, pool: "all")
    a = Array.new(150) { first.draw(profile: "dry")[:prog] }
    state = JSON.parse(JSON.generate(first.to_h))
    second = Playlist.new(DATA, Random.new(2), state, pool: "all")
    b = Array.new(PROGRESSIONS.size - 150) { second.draw(profile: "dry")[:prog] }
    assert_equal PROGRESSIONS.size, (a + b).uniq.size
    assert_equal (a + b).size, (a + b).uniq.size, "the 105 of the first cycle each came once across the restart"
    assert_equal "1/#{PROGRESSIONS.size}", Playlist.new(DATA, Random.new(3), {}, pool: "all").tap { |l| l.draw }.then { |l| l.instance_variable_get(:@bags)["progressions"].position }
  end

  # ------------------------------------------------------------- the harmony audit

  # Every note event any arp or repeat style plays, for every progression, is a tone of the
  # chord it sits in (so also of its scale); the events are read before any audio is made.
  def test_every_note_event_is_a_chord_tone_across_all_progressions_and_styles
    played = 0
    outside = []
    styles = [["arp", DATA.dig("arp", "styles").keys], ["repeat", DATA.dig("comp", "styles").keys]]
    PROGRESSIONS.each_with_index do |names, index|
      voicings = Chords.midi_notes(names)
      styles.each do |mode, keys|
        keys.each do |style|
          seq = sequencer("dry", seed: index)
          settings = mode == "arp" ? seq.arp_settings(nil, style:) : seq.comp_settings(style)
          settings = settings.merge("modifiers" => [])
          streams = seq.note_events(names, 88.0, 4.0, settings, mode)
          streams.each_with_index do |plucks, i|
            chord = Chords.parse(names[i])
            allowed = (chord[:tones].map { |t| (chord[:pc] + t) % 12 } + [chord[:bass] || chord[:pc]]).uniq
            plucks.flat_map { |p| Array(p.midi) }.each do |n|
              played += 1
              outside << [index, names[i], style, n] unless allowed.include?(n % 12)
            end
            assert_equal voicings[i].size >= 3, true
          end
        end
      end
    end
    assert_operator played, :>, 10_000
    assert_empty outside.first(5), "#{outside.size} of #{played} note events fall outside their chord"
  end

  def test_the_echo_forgets_the_old_chord_at_a_chord_change
    d = 2000
    input = Array.new(d * 20, 0.0)
    input[10] = 1.0
    plain = Echo.process(input, delay: d.to_f / SAMPLE_RATE, heads: [1], intensity: 0.8, volume: 1.0, lowpass: nil, saturation: 0.0, tail: 0.1)
    cut = Echo.process(input, delay: d.to_f / SAMPLE_RATE, heads: [1], intensity: 0.8, volume: 1.0, lowpass: nil, saturation: 0.0, tail: 0.1, resets: [d * 10])
    assert_operator plain[(d * 10) + 100, d * 5].map(&:abs).max, :>, 0.05, "without the reset the repeats go on over the next chord"
    assert_in_delta 0.0, cut[(d * 10) + 10, d * 5].map(&:abs).max, 1e-9
    assert_equal plain.first(d * 10), cut.first(d * 10)
  end

  def test_unison_detune_stays_within_six_cents
    DATA.fetch("groove_profiles").each_key do |name|
      assert_operator 1200 * Math.log2(1 + sequencer(name).detune), :<=, 6.1, name
    end
  end

  # ------------------------------------------------------------- the sidechain

  def test_the_pump_ducks_the_chords_on_a_kick_and_other_profiles_do_not
    buf = Array.new(SAMPLE_RATE, 0.5)
    hits = [["kick", 0.1]]
    ducked = sequencer("pump").duck(buf, hits)
    start = (0.1 * SAMPLE_RATE).to_i
    assert_operator ducked[start], :<, buf[start] * 0.6
    assert_operator ducked[start + (0.5 * SAMPLE_RATE).to_i], :>, 0.47
    assert_equal buf, sequencer("lush").duck(buf, hits)
    assert_equal buf, sequencer("pump").duck(buf, [["snare", 0.1]])
  end

  # ------------------------------------------------------------- MIDI

  def read_midi(path)
    bytes = File.binread(path)
    assert_equal "MThd", bytes.byteslice(0, 4)
    assert_equal [0, 1, 480], bytes.byteslice(8, 6).unpack("nnn")
    assert_equal "MTrk", bytes.byteslice(14, 4)
    track = bytes.byteslice(22, bytes.byteslice(18, 4).unpack1("N"))
    events = []
    pos = 0
    tick = 0
    while pos < track.bytesize
      delta = 0
      loop do
        byte = track.getbyte(pos)
        pos += 1
        delta = (delta << 7) | (byte & 0x7f)
        break if byte < 0x80
      end
      tick += delta
      status = track.getbyte(pos)
      if status == 0xFF
        events << [tick, :meta, track.getbyte(pos + 1)]
        pos += 3 + track.getbyte(pos + 2)
      else
        events << [tick, status, track.getbyte(pos + 1), track.getbyte(pos + 2)]
        pos += 3
      end
    end
    events
  end

  def test_midi_export_rereads_as_the_chords_and_the_drums
    Dir.mktmpdir do |dir|
      names = %w[Cm9 Fm9 Bbm9]
      hits = sequencer("early_snare_late_hats").drum_hits("syncopated_swing", 88.0, 3 * 4 * 60.0 / 88)
      path = File.join(dir, "x.mid")
      MIDI.write(path, names, 88.0, 4.0, hits)
      events = read_midi(path)
      assert_equal [:meta, 0x2F], events.last[1, 2]
      ons = events.select { |e| e[1].is_a?(Integer) && (e[1] & 0xf0) == 0x90 }
      assert_equal Chords.midi_notes(names).flatten.sort, ons.select { |e| e[1] == 0x90 }.map { |e| e[2] }.sort
      drums = ons.select { |e| e[1] == 0x99 }
      assert_equal hits.size, drums.size
      assert_equal [36, 38, 42], drums.map { |e| e[2] }.uniq.sort
      assert_equal events.map(&:first), events.map(&:first).sort, "ticks never run backwards"
      offs = events.select { |e| e[1].is_a?(Integer) && (e[1] & 0xf0) == 0x80 }
      assert_equal ons.size, offs.size, "every note that starts also ends"
    end
  end

  # ------------------------------------------------------------- the command

  def test_list_prints_the_index_and_the_chords
    out, err, status = run_dilla("--list", chdir: Dir.tmpdir)
    assert status.success?, err
    assert_match(/^Progressions:\n\s+0  #{Regexp.escape(PROGRESSIONS.first.join(' '))}\n/, out)
    assert_includes out, "Drum patterns: #{DATA['drum_patterns'].keys.join(', ')}"
    assert_includes out, "Groove profiles: #{DATA['groove_profiles'].keys.join(', ')}"
  end

  def test_a_render_is_a_16_bit_mono_wav_the_same_seed_repeats_and_it_is_not_silent
    Dir.mktmpdir do |dir|
      a = File.join(dir, "a.wav")
      b = File.join(dir, "b.wav")
      args = ["--progression", "7", "--drums", "offbeat_inversion", "--profile", "pump", "--seed", "3", "--beats", "2",
              "--midi", File.join(dir, "a.mid")]
      [a, b].each do |out|
        _o, err, status = run_dilla(*args, "--out", out, chdir: dir)
        assert status.success?, err
      end
      assert_equal File.binread(a), File.binread(b)
      bytes = File.binread(a)
      assert_equal "RIFF", bytes.byteslice(0, 4)
      assert_equal [1, 44_100], [bytes.byteslice(22, 2).unpack1("v"), bytes.byteslice(24, 4).unpack1("V")]
      assert_operator bytes.byteslice(44..).unpack("s<*").map(&:abs).max, :>, 1000
      assert File.file?(File.join(dir, "a.mid"))
    end
  end

  def test_quick_renders_the_first_progression_to_out_in_the_working_directory
    Dir.mktmpdir do |dir|
      _out, err, status = run_dilla("--quick", chdir: dir)
      assert status.success?, err
      assert File.file?(File.join(dir, "out", "quick.wav"))
    end
  end

  def test_an_unknown_progression_pattern_or_profile_is_refused
    Dir.mktmpdir do |dir|
      out = File.join(dir, "x.wav")
      [%w[--progression 9999], %w[--progression 0 --drums nope], %w[--progression 0 --profile nope]].each do |args|
        _o, _e, status = run_dilla(*args, "--out", out, chdir: dir)
        refute status.success?, args.join(" ")
      end
    end
  end

  def test_synthesized_drums_are_finite_and_have_distinct_transients
    drums = Drums.new(123)
    [drums.kick, drums.snare, drums.hat].each do |hit|
      assert_operator hit.length, :>, 100
      assert(hit.all? { |sample| sample.finite? })
      assert_operator hit.map(&:abs).max, :>, 0.05
    end
  end

  def test_pure_tone_has_no_significant_upper_harmonics
    tone = Synth.pure_note(440.0, 0.6, amp: 0.5, release: 0.12)
    fundamental = tone_energy(tone, 440.0)
    assert_operator fundamental, :>, 0.1
    assert_operator tone_energy(tone, 880.0), :<, fundamental * 0.01
    assert_operator tone_energy(tone, 1320.0), :<, fundamental * 0.01
  end

  def test_each_drum_hit_varies_and_the_drum_bus_receives_sonitex_and_vcs
    seq = sequencer("dry", seed: 31)
    hits = [["snare", 0.1], ["snare", 0.5]]
    plain = seq.overlay_drums(Array.new(SAMPLE_RATE, 0.0), hits, {"snare" => -3.0})
    coloured = seq.overlay_drums(
      Array.new(SAMPLE_RATE, 0.0), hits, {"snare" => -3.0}, 0.55,
      sonitex: {"preset" => DATA.dig("sonitex", "presets", "dusty_warm"), "instances" => 2},
      tape: "heavy"
    )
    assert(plain.all?(&:finite?))
    assert(coloured.all?(&:finite?))
    refute_equal plain, coloured
    assert_operator coloured.map(&:abs).max, :<=, 1.0
    first = plain[(0.1 * SAMPLE_RATE).to_i, 4000]
    second = plain[(0.5 * SAMPLE_RATE).to_i, 4000]
    refute_equal first, second, "each snare should get its own deterministic noise/transient"
  end

  def test_analogue_tape_is_static_bounded_and_changes_the_drum_bus
    input = Array.new(SAMPLE_RATE) do |i|
      0.5 * Math.sin(2.0 * Math::PI * 65.0 * i / SAMPLE_RATE) +
        0.2 * Math.sin(2.0 * Math::PI * 6800.0 * i / SAMPLE_RATE)
    end
    output = Colour.tape(input, amount: 1.0)
    assert(output.all?(&:finite?))
    refute_equal input, output
    assert_operator output.map(&:abs).max, :<, 1.0
    assert_same input, Colour.tape(input, amount: 0.0)
  end

  # ------------------------------------------------------------- kits and the new drum engine

  ROLES = %w[kick snare clap hat open rim tom perc].freeze

  def kit_sounds(name, seed = 3) = Percussion.kit(name, DATA, seed)

  def spectrum_share(buf, above_hz)
    low = Percussion.lowpass(buf, above_hz)
    high = buf.each_index.map { |i| buf[i] - low[i] }
    high.sum { |v| v * v } / [buf.sum { |v| v * v }, 1e-12].max
  end

  def test_every_kit_covers_every_role_and_every_voice_is_audible_and_under_full_scale
    assert_equal %w[kit_909 kit_detroit kit_dust kit_fm kit_industrial kit_world], DATA.fetch("kits").keys.sort
    DATA.fetch("kits").each_key do |name|
      sounds = kit_sounds(name)
      assert_equal ROLES.sort, sounds.keys.sort, name
      sounds.each do |role, buf|
        assert_operator buf.size, :>, 100, "#{name} #{role}"
        assert(buf.all?(&:finite?), "#{name} #{role}")
        assert_operator buf.map(&:abs).max, :>, 0.05, "#{name} #{role} is audible"
        assert_operator buf.map(&:abs).max, :<, 1.0, "#{name} #{role} stays under full scale"
      end
    end
  end

  def test_a_kick_body_sits_at_its_tuned_frequency_and_the_909_hat_is_bright
    DATA.fetch("kick_styles").each do |style, spec|
      kick = Percussion.techno_kick(spec, Random.new(1))
      tail = kick[(0.2 * SAMPLE_RATE).to_i, (0.1 * SAMPLE_RATE).to_i]
      crossings = tail.each_cons(2).count { |a, b| a.negative? != b.negative? }
      assert_in_delta spec["body"], crossings / 2 / 0.1, 14, "#{style}: the body settles near its tuning"
    end
    hat = kit_sounds("kit_909").fetch("hat")
    assert_operator spectrum_share(hat, 6000.0), :>, 0.15, "909 hat energy above 6 kHz"
    assert_operator spectrum_share(hat, 6000.0), :>, spectrum_share(kit_sounds("kit_909").fetch("kick"), 6000.0) * 20
    open = kit_sounds("kit_909").fetch("open")
    assert_operator open.size, :>, hat.size * 3
  end

  def test_a_seed_names_a_kit_and_another_seed_changes_the_noise
    assert_equal kit_sounds("kit_909", 4), kit_sounds("kit_909", 4)
    refute_equal kit_sounds("kit_909", 4).fetch("clap"), kit_sounds("kit_909", 5).fetch("clap")
  end

  def test_a_unknown_kit_or_voice_is_refused
    assert_raises(ArgumentError) { Percussion.voice({ "voice" => "nope" }, DATA, Random.new(1)) }
  end

  def test_a_closed_hat_chokes_the_open_one_before_it
    seq = sequencer("dry")
    seq.instance_variable_set(:@kit, "kit_909")
    silent = Array.new(SAMPLE_RATE, 0.0)
    free = seq.overlay_drums(silent, [["open", 0.1, 1.0]])
    choked = seq.overlay_drums(silent, [["open", 0.1, 1.0], ["hat", 0.2, 0.0001]])
    tail = ((0.3 * SAMPLE_RATE).to_i)..((0.4 * SAMPLE_RATE).to_i)
    assert_operator choked[tail].map(&:abs).max, :<, free[tail].map(&:abs).max * 0.2
  end

  def pocket_hits(name, seconds = 60.0, profile: "dry", seed: 7, bpm: 140.0)
    sequencer(profile, seed:).drum_hits(name, bpm, seconds)
  end

  def test_velocity_aware_cells_make_ghosts_and_ratchets_real
    data = JSON.parse(JSON.generate(DATA))
    data["drum_patterns"]["probe"] = { "kick" => [1] + [0] * 15, "hat" => [0, 0.35, 0] + [0] * 12 + [[0.8, 3]], "snare" => [0] * 16 }
    hits = sequencer("dry", data:).drum_hits("probe", 120.0, 2.0)
    assert_includes hits.map { |_, _, v| v.round(2) }, 0.35
    roll = hits.select { |r, t, _| r == "hat" && t > 1.8 }
    assert_equal [0.8, 0.704, 0.608], roll.map { |_, _, v| v.round(3) }
  end

  def test_a_rotation_never_plays_the_same_pattern_twice_running_and_is_seeded
    names = %w[techno_909 electro_break halftime_heavy techno_roll]
    seq = sequencer("dry", seed: 3)
    picks = seq.phrase_patterns(names, 40)
    picks.each_cons(2) { |a, b| refute_equal a, b }
    assert_equal names.sort, picks.uniq.sort
    assert_equal picks, sequencer("dry", seed: 3).phrase_patterns(names, 40)
    refute_equal picks, sequencer("dry", seed: 4).phrase_patterns(names, 40)
    hits = seq.drum_hits(names, 140.0, 60.0 / 140 * 4 * 12)
    assert_operator hits.map { |r, *| r }.uniq.size, :>=, 3
  end

  def test_mutation_keeps_the_grid_length_and_leaves_the_downbeat_kick_alone_and_bars_differ
    seq = sequencer("techno_arp", seed: 5)
    pattern = DATA.dig("drum_patterns", "techno_909")
    rows = (1..24).map { |bar| seq.bar_rows(pattern, 0, bar) }
    rows.each do |r|
      r.each { |role, row| assert_equal 16, row.size, role }
      assert_operator r.fetch("kick")[0], :>, 0
    end
    assert_operator rows.map { |r| JSON.generate(r) }.uniq.size, :>, 8, "no two bars are all alike"
    assert_equal rows, (1..24).map { |bar| sequencer("techno_arp", seed: 5).bar_rows(pattern, 0, bar) }
  end

  def test_snare_density_two_doubles_the_back_snares_and_raises_the_snare_stem
    one = sequencer("dry", seed: 2)
    two = sequencer("techno_arp", seed: 2)
    pattern = DATA.dig("drum_patterns", "techno_909")
    count = ->(seq) { (4..11).sum { |bar| seq.bar_rows(pattern, 0, bar).fetch("snare").count { |c| c.is_a?(Array) || c.to_f.positive? } } }
    assert_operator count.call(two), :>=, count.call(one) * 1.9
    kit = kit_sounds("kit_909")
    stem = lambda do |seq|
      silent = Array.new(SAMPLE_RATE * 8, 0.0)
      hits = seq.drum_hits("techno_909", 138.0, 8.0).select { |r, *| r == "snare" }
      seq.overlay_drums(silent, hits, { "snare" => 0.0 })
    end
    rms = ->(b) { Math.sqrt(b.sum { |v| v * v } / b.size) }
    two.instance_variable_set(:@kit, "kit_909")
    one.instance_variable_set(:@kit, "kit_909")
    assert_operator rms.call(stem.call(two)), :>, rms.call(stem.call(one)) * 1.2
    assert_equal ROLES.sort, kit.keys.sort
  end

  def test_unsynced_layers_realign_only_after_the_least_common_multiple_of_their_lengths
    pattern = DATA.dig("drum_patterns", "eclectic")
    lengths = pattern.fetch("layers").map { |l| l["length"] }
    assert_operator lengths.uniq.size, :>=, 3
    assert_operator lengths.reduce(1, :lcm), :>, 16 * 4, "the combined layers repeat after more bars than a phrase"
    hits = ->(layer) { (0...lengths.reduce(1, :lcm)).select { |i| layer["hits"][i % layer["length"]].to_f.positive? } }
    patterns = pattern.fetch("layers").map { |l| hits.call(l) }
    assert_equal patterns.size, patterns.uniq.size
  end

  def test_eclectic_keeps_the_kick_on_one_in_about_forty_percent_of_bars_and_offsets_inside_the_clamp
    seq = sequencer("eclectic", seed: 11)
    pattern = DATA.dig("drum_patterns", "eclectic")
    plain = JSON.parse(JSON.generate(DATA))
    plain["drum_patterns"]["eclectic"].delete("fill")
    ones = (1..400).count { |bar| seq.bar_rows(pattern, 0, bar).fetch("kick")[0].to_f.positive? }
    assert_in_delta 0.4, ones / 400.0, 0.1
    step = 60.0 / 82 / 4
    hits = sequencer("eclectic", seed: 11, data: plain).drum_hits("eclectic", 82.0, 90.0)
    assert(hits.all? { |_, t, _| (t - ((t / step).round * step)).abs <= MAX_OFFSET + 1e-9 }, "fine-grid offsets stay inside the clamp")
    assert_equal hits, sequencer("eclectic", seed: 11, data: plain).drum_hits("eclectic", 82.0, 90.0)
  end

  def test_the_new_profiles_carry_a_kit_a_pattern_and_a_tempo_and_render_with_drums
    %w[techno_arp industrial_arp eclectic].each do |name|
      profile = DATA.dig("groove_profiles", name)
      assert_includes DATA.fetch("kits"), profile.fetch("kit")
      assert_includes DATA.fetch("drum_patterns"), profile.fetch("drums")
      assert_includes DATA.fetch("play_profiles"), name
    end
    assert DATA.dig("groove_profiles", "techno_arp", "bpm").between?(128, 150)
    Dir.mktmpdir do |dir|
      out = File.join(dir, "t.wav")
      o, err, status = run_dilla("--progression", "4", "--beats", "2", "--profile", "techno_arp", "--seed", "3", "--out", out, chdir: dir)
      assert status.success?, err
      assert_match(/drums=techno_909/, o)
      samples = File.binread(out).byteslice(44..).unpack("s<*")
      assert_operator samples.map(&:abs).max, :<=, 32_767
      assert_operator samples.map(&:abs).max, :>, 5000
    end
  end

  def test_a_chord_holds_two_bars_by_default_and_chord_changes_land_on_bar_lines
    Dir.mktmpdir do |dir|
      out = File.join(dir, "x.wav")
      _o, err, status = run_dilla("--progression", "2", "--profile", "dry", "--mode", "pad", "--out", out, chdir: dir)
      assert status.success?, err
      seconds = (File.size(out) - 44) / 2.0 / SAMPLE_RATE
      assert_operator seconds, :>=, (4 * 8 * 60.0 / 88) - 0.02
      assert_operator seconds, :<=, (4 * 8 * 60.0 / 88) + 1.6, "the last notes ring out"
    end
    assert_equal 8.0, sequencer("dry").beats
    assert_equal 2 * 4 * 60.0 / 88, 8 * 60.0 / 88
  end

  def test_a_chord_holds_two_bars_by_default_and_chord_changes_land_on_bar_lines
    Dir.mktmpdir do |dir|
      out = File.join(dir, "x.wav")
      _o, err, status = run_dilla("--progression", "2", "--profile", "dry", "--mode", "pad", "--out", out, chdir: dir)
      assert status.success?, err
      seconds = (File.size(out) - 44) / 2.0 / SAMPLE_RATE
      assert_operator seconds, :>=, (4 * 8 * 60.0 / 88) - 0.02
      assert_operator seconds, :<=, (4 * 8 * 60.0 / 88) + 1.6, "the last notes ring out"
    end
    assert_equal 8.0, sequencer("dry").beats
    assert_equal 2 * 4 * 60.0 / 88, 8 * 60.0 / 88
  end

  # ------------------------------------------------------------- the tape stack

  def programme(seconds = 3.0, rms: 0.1)
    raw = Synth.chord([110.0, 164.8, 220.0, 277.2, 329.6], seconds)
    scale = rms / Tape.rms(raw)
    raw.map { |x| x * scale }
  end

  def test_zero_tape_machines_hand_back_the_very_same_signal
    buf = programme(0.5)
    assert_same buf, Tape.apply(buf, instances: 0)
    assert_same buf, Tape.apply(buf, instances: -2)
  end

  def test_a_stack_keeps_the_programme_within_one_decibel_of_its_input_level
    [[1, 1.0], [4, 1.0], [4, 2.5], [8, 1.0]].each do |instances, drive|
      [0.03, 0.1, 0.25].each do |level|
        buf = programme(3.0, rms: level)
        out = Tape.apply(buf, instances:, drive:, seed: 4, config: DATA.fetch("tape"))
        assert_in_delta 0.0, Tape.db(Tape.rms(out) / Tape.rms(buf)), 1.0, "#{instances} machines, drive #{drive}, rms #{level}"
      end
    end
  end

  def test_the_loop_remembers_the_way_the_signal_came_so_the_curve_is_not_a_waveshaper
    loop_model = Tape::Hysteresis.new
    rising = loop_model.step(0.5)
    loop_model.step(1.0)
    falling = loop_model.step(0.5)
    refute_in_delta rising, falling, 0.01
  end

  def test_tape_adds_odd_harmonics_to_a_sine_and_keeps_it_exactly_periodic
    sine = Array.new(SAMPLE_RATE) { |i| 0.2 * Math.sin(2 * Math::PI * 441 * i / SAMPLE_RATE) } # 100 samples a cycle
    out = Tape.apply(sine, instances: 4, seed: 1, config: DATA.fetch("tape")).last(10_000)
    fundamental = Tape.goertzel(out, 441)
    third = Tape.goertzel(out, 1323)
    assert_operator Tape.db(third / fundamental), :>, -45.0, "the medium is heard"
    assert_operator Tape.db(third / fundamental), :<, -15.0, "and stays a colour"
    drift = (0...9_000).map { |i| (out[i] - out[i + 100]).abs }.max
    assert_operator drift, :<, 2e-4, "a cycle repeats the one before: no wow, no flutter"
  end

  def test_more_drive_makes_more_third_harmonic_and_the_stack_has_the_machines_asked_for
    sine = Array.new(SAMPLE_RATE) { |i| 0.2 * Math.sin(2 * Math::PI * 441 * i / SAMPLE_RATE) }
    shares = [0.5, 1.0, 2.0].map do |drive|
      out = Tape.apply(sine, instances: 2, drive:, seed: 1, config: DATA.fetch("tape")).last(10_000)
      Tape.goertzel(out, 1323) / Tape.goertzel(out, 441)
    end
    assert_equal shares.sort, shares
    assert_equal 4, Tape::Stack.new(instances: 4, drive: 1.0, seed: 1, config: DATA.fetch("tape")).machines.size
  end

  def test_the_same_seed_gives_the_same_tape_and_another_seed_a_different_machine
    buf = programme(1.0)
    config = DATA.fetch("tape")
    a = Tape.apply(buf, instances: 3, seed: 8, config:)
    assert_equal a, Tape.apply(buf, instances: 3, seed: 8, config:)
    refute_equal a, Tape.apply(buf, instances: 3, seed: 9, config:)
  end

  def test_a_signal_cut_into_chunks_leaves_the_stack_as_one_call_does
    buf = programme(1.5)
    config = DATA.fetch("tape")
    whole = Tape::Stack.new(instances: 3, seed: 2, config:).process(buf)
    stack = Tape::Stack.new(instances: 3, seed: 2, config:)
    parts = buf.each_slice(4410 + 17).flat_map { |chunk| stack.process(chunk) }
    assert_equal whole.size, parts.size
    assert_in_delta 0.0, whole.zip(parts).map { |x, y| (x - y).abs }.max, 1e-12
  end

  def test_the_ceiling_is_the_last_stage_and_bends_only_the_peaks
    quiet = [0.1, -0.5, 0.79]
    assert_equal quiet, Tape.ceiling(quiet)
    loud = Tape.ceiling([0.9, -1.4, 5.0, -80.0])
    assert(loud.all? { |v| v.abs < 0.97 + 1e-9 })
    assert_operator loud[0], :<, 0.9
  end

  def test_the_render_ends_on_the_tape_and_the_flag_reaches_it
    Dir.mktmpdir do |dir|
      args = ["--progression", "2", "--profile", "dry", "--mode", "pad", "--beats", "2", "--seed", "6"]
      off = File.join(dir, "off.wav")
      on = File.join(dir, "on.wav")
      out, err, status = run_dilla(*args, "--tape", "0", "--out", off, chdir: dir)
      assert status.success?, err
      assert_includes out, "tape=0"
      out, err, status = run_dilla(*args, "--tape", "2", "--tape-drive", "1.5", "--out", on, chdir: dir)
      assert status.success?, err
      assert_includes out, "tape=2"
      refute_equal File.binread(off), File.binread(on)
      a, b = [off, on].map { |path| File.binread(path).byteslice(44..).unpack("s<*").map { |s| s / 32_768.0 } }
      assert_equal a.size, b.size
      assert_in_delta 0.0, Tape.db(Tape.rms(b) / Tape.rms(a)), 1.0
      assert_operator b.map(&:abs).max, :<, 0.97
    end
  end

  # ------------------------------------------------------------- the patch bag in play

  def test_play_prints_the_patch_of_every_pass_and_saves_the_bag
    Dir.mktmpdir do |dir|
      player, = fake_player(dir)
      out, err, status = run_dilla("--play", "--player", player, "--passes", "3", "--beats", "1", "--seed", "12",
                                   "--profile", "dry", "--mode", "pad", "--patch-per-chord", "--tape", "0", "--decks", "1", "--out", File.join(dir, "x.wav"), chdir: dir)
      assert status.success?, err
      voices = out.scan(/^pass \d+: .* voice=(\S+) \(patch (\d+)\/(\d+)\)/)
      assert_equal 3, voices.size
      voices.each { |list, _, size| assert_equal PLAYABLE.size, size.to_i, list }
      assert(voices.all? { |list, *| list.split(">").all? { |name| DATA.fetch("voices").key?(name) } })
      assert_includes JSON.parse(File.read(File.join(dir, "play_state.json"))).keys, "voices"
    end
  end

  # ------------------------------------------------------------- polysynth, dub and organ voices

  NEW_VOICES = %w[prophet_pad prophet_warm oberheim_pad juno_strings solina_ensemble cs80_ensemble ruby_strings
                  dub_stab dub_pad dub_bass dub_bubble organ fluid_strings fluid_strings_slow fluid_synth_strings fluid_choir fluid_warm_pad].freeze

  def test_the_named_voices_exist_and_every_voice_has_a_group
    NEW_VOICES.each { |name| assert_includes DATA.fetch("voices"), name }
    DATA.fetch("voices").each { |name, spec| assert_kind_of String, spec["group"], name }
  end

  def test_no_voice_row_names_a_modulation_and_unison_detune_stays_within_six_cents
    assert_nil DATA.fetch("voices").to_json[/lfo|tremolo|vibrato|chorus|wow|flutter/i]
    DATA.fetch("voices").each do |name, spec|
      next unless spec["family"] == "moog"

      assert_operator spec.fetch("detune").map(&:abs).max, :<=, 6.0, name if NEW_VOICES.include?(name)
    end
  end

  def test_a_pad_voice_makes_the_notes_of_a_chord_at_a_sane_level
    seq = sequencer("dry")
    seq.tempo = 88.0
    reference = Tape.rms(seq.render_chords(%w[Abmaj7], 88.0, 2.0, voice: seq.voice_spec("moog_pad")))
    %w[prophet_pad prophet_warm oberheim_pad juno_strings solina_ensemble cs80_ensemble ruby_strings dub_pad dub_bubble organ].each do |name|
      level = Tape.rms(seq.render_chords(%w[Abmaj7], 88.0, 2.0, voice: seq.voice_spec(name)))
      assert_in_delta 0.0, Tape.db(level / reference), 4.0, name
    end
  end

  def test_the_bubble_is_gated_by_its_pattern_and_not_by_an_oscillator
    spec = DATA.fetch("voices").fetch("dub_bubble").merge("pattern" => "x.", "cell_steps" => 1, "slew" => 0.002)
    step = 0.02
    samples = Voices.note(spec, 57, 0.4, 0.2, step:)
    cell = (step * SAMPLE_RATE).round
    open = Tape.rms(samples[(cell * 4) + 500, 250])
    shut = Tape.rms(samples[(cell * 5) + 500, 250])
    assert_operator open, :>, 0.02
    assert_operator Tape.db(open / [shut, 1e-9].max), :>, 40.0, "a shut cell is silent"
    assert_in_delta open, Tape.rms(samples[(cell * 8) + 500, 250]), open * 0.1, "the pattern comes round again"
    assert_operator Tape.db(Tape.rms(samples[(cell * 9) + 500, 250]) / open), :<, -40.0
  end

  def test_the_organ_sounds_the_ranks_of_its_registration_and_a_chiff_that_dies_in_fifteen_milliseconds
    spec = DATA.fetch("voices").fetch("organ")
    window = ->(samples) { samples[SAMPLE_RATE / 5, SAMPLE_RATE / 5] }
    heard = ->(name, ratio) { Tape.goertzel(window.call(Voices.note(spec, 57, 0.6, 0.2, registration: spec["registrations"][name])), 220.0 * ratio) }
    assert_operator Tape.db(heard.call("principal", 2) / heard.call("principal", 1)), :<, -60.0, "an eight foot alone"
    assert_operator Tape.db(heard.call("octave", 2) / heard.call("octave", 1)), :>, -6.0, "and with the four foot"
    assert_operator heard.call("mixture", 6), :>, 0.01
    assert_operator heard.call("mixture", 8), :>, 0.005
    assert_operator heard.call("full", 0.5), :>, 0.01, "sixteen foot"
    loud = Voices.note(spec, 57, 0.6, 0.2)
    quiet = Voices.note(spec.merge("chiff" => spec["chiff"].merge("level" => 0.0)), 57, 0.6, 0.2)
    chiff = loud.zip(quiet).map { |a, b| a - b }
    early = Tape.rms(chiff.first(SAMPLE_RATE * 15 / 1000))
    late = Tape.rms(chiff[SAMPLE_RATE * 80 / 1000, SAMPLE_RATE * 40 / 1000])
    assert_operator Tape.db(early / [late, 1e-9].max), :>, 20.0
    assert_operator early, :>, 0.001
  end

  def test_the_organ_has_no_tremulant_a_held_note_is_periodic
    spec = DATA.fetch("voices").fetch("organ")
    note = Voices.note(spec, 69, 1.0, 0.2, registration: spec["registrations"]["octave"]) # 440 Hz: 100.227 samples a cycle
    cycle = (SAMPLE_RATE / 440.0)
    peaks = (0..8).map { |k| note[(SAMPLE_RATE * 0.3).round + (cycle * k).round, 50].map(&:abs).max }
    assert_in_delta 0.0, peaks.max - peaks.min, 0.002
  end

  def test_a_soundfont_voice_writes_a_midi_file_and_reads_a_wav_back
    Dir.mktmpdir do |dir|
      path = File.join(dir, "n.mid")
      MIDI.write_notes(path, [[0.0, 0.5, 60, 90], [0.25, 0.5, 64, 80]], program: 52)
      bytes = File.binread(path)
      assert_equal "MThd", bytes.byteslice(0, 4)
      assert_includes bytes, "\xC0\x34".b, "program change to 52"
      assert_includes bytes, "\x90\x3C\x5A".b, "middle C on at velocity 90"
      assert_includes bytes, "\x90\x40\x50".b, "and the E above it"
      assert bytes.end_with?("\xFF\x2F\x00".b), "ends the track"
      wav = File.join(dir, "s.wav")
      pcm = [1000, -1000, 2000, 0].pack("s<*")
      File.binwrite(wav, "RIFF".b + [36 + pcm.bytesize].pack("V") + "WAVEfmt ".b + [16, 1, 2, SAMPLE_RATE, SAMPLE_RATE * 4, 4, 16].pack("VvvVVvv") + "data".b + [pcm.bytesize].pack("V") + pcm)
      assert_equal [0.0, 1000 / 32_768.0], Fluid.read(wav)
    end
  end

  def test_a_truncated_soundfont_is_not_whole
    Dir.mktmpdir do |dir|
      cut = File.join(dir, "cut.sf2")
      File.binwrite(cut, "RIFF".b + [5000].pack("V") + "sfbk".b + ("x" * 100))
      refute Fluid.whole?(cut)
      whole = File.join(dir, "whole.sf2")
      File.binwrite(whole, "RIFF".b + [20].pack("V") + "sfbk".b + ("x" * 16))
      assert Fluid.whole?(whole)
      refute Fluid.whole?(File.join(dir, "absent.sf2"))
    end
  end

  def test_without_a_soundfont_the_rotation_leaves_soundfont_voices_out_and_a_named_one_falls_back_aloud
    saved = ENV.fetch("DILLA_SOUNDFONT", nil)
    ENV["DILLA_SOUNDFONT"] = "/nonexistent/none.sf2"
    refute Fluid.available?(DATA["voices"]["fluid_choir"])
    assert_includes Fluid.missing(DATA["voices"]["fluid_choir"]).to_s, "soundfont"
    names = Playlist.new(DATA, Random.new(1)).voice_names
    assert(names.none? { |name| DATA["voices"][name]["family"] == "fluid" })
    assert_includes names, "ruby_strings"
    _out, err = capture_io { @spec = sequencer("dry").voice_spec("fluid_choir") }
    assert_equal "ruby_strings", @spec["name"]
    assert_includes err, "fluid_choir"
    assert_includes err, "ruby_strings"
  ensure
    saved ? ENV["DILLA_SOUNDFONT"] = saved : ENV.delete("DILLA_SOUNDFONT")
  end

  def test_a_soundfont_voice_renders_through_fluidsynth_when_it_is_there
    skip "fluidsynth or a whole soundfont is missing: #{Fluid.missing(DATA['voices']['fluid_strings'])}" unless Fluid.available?(DATA["voices"]["fluid_strings"])

    seq = sequencer("dry")
    spec = seq.voice_spec("fluid_strings")
    assert_equal "fluid", spec["family"]
    plucks = [Pluck.new(0.1, 0.0, [57, 64], 0.8, 0.8)]
    out = Fluid.render(plucks, spec)
    assert_operator out.size, :>, SAMPLE_RATE
    assert_operator out.first((0.08 * SAMPLE_RATE).to_i).map(&:abs).max, :<, 0.001, "nothing before the note"
    assert_operator out[(0.5 * SAMPLE_RATE).to_i, 2000].map(&:abs).max, :>, 0.01
    buf = Array.new(2 * SAMPLE_RATE, 0.0)
    seq.sound(buf, plucks, spec)
    assert_operator buf.map(&:abs).max, :>, 0.01
  end

  # ------------------------------------------------------------- the dub profile

  def test_the_dub_profile_skanks_on_the_upbeats_with_bass_pad_and_bubble_under_it
    profile = DATA.fetch("groove_profiles").fetch("dub_dark")
    assert_includes DATA.fetch("play_profiles"), "dub_dark"
    assert_includes 72..80, profile.fetch("bpm")
    assert_equal "..x...x...x...x.", DATA.dig("comp", "styles", profile.dig("repeat", "style"), "pattern")
    assert_equal %w[dub_bass dub_pad dub_bubble], profile.fetch("layers").map { |l| l["voice"] }
    assert((profile.fetch("drums") & %w[one_drop steppers]).size == 2)
    assert_operator profile.dig("echo", "intensity"), :>=, 0.75
    assert_operator profile.dig("texture", "spring"), :>, 0.0
    buf = render(DATA, prog: 7, seed: 4, profile: "dub_dark", beats: 2.0, tape: 0, buffer_only: true)
    assert_operator buf.map(&:abs).max, :<=, 1.0
    assert_operator Tape.rms(buf), :>, 0.02
  end

  def test_a_layer_can_play_only_the_bass_of_each_chord
    seq = sequencer("dry")
    layers = [{ "voice" => "dub_bass", "mode" => "held", "notes" => "bass", "gain_db" => 0 }]
    options = { layers:, transpose: 0 }
    all = [{ "voice" => "dub_bass", "mode" => "held", "gain_db" => 0 }]
    bass = render_layers(Array.new(SAMPLE_RATE * 4, 0.0), seq, %w[Cm9], 120.0, 4.0, options, search: true)
    full = render_layers(Array.new(SAMPLE_RATE * 4, 0.0), seq, %w[Cm9], 120.0, 4.0, options.merge(layers: all), search: true)
    upper = Chords.hz(Chords.midi_notes(%w[Cm9]).first[3])
    heard = ->(buf) { Tape.goertzel(buf[SAMPLE_RATE, SAMPLE_RATE], upper) }
    assert_operator heard.call(full), :>, 10 * heard.call(bass), "the upper tones belong to the full chord, not to the bass"
    assert_operator Tape.rms(bass), :>, 0.0
  end

  def test_the_echo_throws_one_bar_in_each_phrase_and_never_the_first
    seq = sequencer("dub_dark", seed: 11)
    send = seq.throws({ "every_bars" => 4, "gain" => 2.6, "base" => 0.3 }, 76.0)
    bar = (4 * 60.0 / 76.0 * SAMPLE_RATE).round
    levels = (0...16).map { |b| send.call((b * bar) + 100) }
    levels.each_slice(4) do |phrase|
      assert_equal 1, phrase.count(2.6)
      assert_equal 3, phrase.count(0.3)
      assert_equal 0.3, phrase.first
    end
    assert_equal levels, (0...16).map { |b| sequencer("dub_dark", seed: 11).throws({ "every_bars" => 4, "gain" => 2.6, "base" => 0.3 }, 76.0).call((b * bar) + 100) }
    assert_nil seq.throws(nil, 76.0)
  end

  def test_a_send_turns_up_what_reaches_the_tape_and_no_send_is_the_old_echo
    input = impulse(10).map { |x| x * 0.01 } # small, so the tape's tanh is a straight line
    args = { delay: 0.05, heads: [1], intensity: 0.5, volume: 1.0, lowpass: nil, saturation: 0.0, tail: 1.0 }
    plain = Echo.process(input, **args)
    assert_equal plain, Echo.process(input, **args, send: ->(_n) { 1.0 })
    louder = Echo.process(input, **args, send: ->(_n) { 3.0 })
    d = (0.05 * SAMPLE_RATE).round
    assert_operator plain[d].abs, :>, 0.001
    assert_in_delta 3.0 * plain[d], louder[d], 1e-4
    assert_equal plain.first(10), louder.first(10)
  end

  def test_the_spring_adds_a_tail_that_dies_away_and_changes_nothing_when_off
    input = impulse(100) + Array.new(SAMPLE_RATE * 2, 0.0)
    assert_same input, FX.spring(input, 0.0)
    wet = FX.spring(input, 0.5)
    assert_equal input.size, wet.size
    assert(wet.all?(&:finite?))
    assert_operator wet[1000, 4000].map(&:abs).max, :>, 0.001, "a tail after the hit"
    assert_operator wet.last(2000).map(&:abs).max, :<, wet[1000, 4000].map(&:abs).max * 0.1, "which dies away"
  end

  # ------------------------------------------------------------- the organ improvisation

  ORGAN = DATA.fetch("organ")

  def organ_pieces(seeds = 1..30)
    ORGAN.fetch("scales").keys.flat_map { |scale| seeds.map { |seed| Organ.compose(seed:, config: ORGAN, bars: 12, scale:) } }
  end

  def test_every_organ_note_is_in_the_declared_scale_and_its_lines_keep_their_ranges
    ranges = ORGAN.fetch("ranges")
    organ_pieces.each do |piece|
      piece.lines.each do |line, notes|
        lo, hi = ranges.fetch(line)
        assert(notes.all? { |n| piece.pcs.include?(n.midi % 12) }, "#{piece.key} #{piece.scale} #{line}")
        assert(notes.all? { |n| n.midi.between?(lo, hi) }, "#{line} stays between #{lo} and #{hi}")
      end
      piece.names.each { |name| Chords.parse(name) }
    end
    assert_equal [36, 48], ranges["pedal"]
    assert_equal [50, 67], ranges["left"]
    assert_equal [60, 84], ranges["right"]
  end

  def test_an_organ_piece_is_deterministic_by_seed_and_the_seed_changes_it
    a = Organ.compose(seed: 7, config: ORGAN)
    assert_equal a.lines.transform_values { |ns| ns.map(&:to_a) }, Organ.compose(seed: 7, config: ORGAN).lines.transform_values { |ns| ns.map(&:to_a) }
    refute_equal a.lines["right"].map(&:to_a), Organ.compose(seed: 8, config: ORGAN).lines["right"].map(&:to_a)
    assert_equal "D", Organ.compose(seed: 1, config: ORGAN, key: "D", scale: "dorian").key
    assert_equal "Bb", Organ.compose(seed: 1, config: ORGAN, key: "A#", scale: "major").key
    assert_raises(ArgumentError) { Organ.compose(seed: 1, config: ORGAN, scale: "whole_tone") }
  end

  def test_phrases_run_two_to_four_bars_fill_the_piece_and_close_on_cadences
    organ_pieces(1..15).each do |piece|
      assert(piece.phrases.all? { |ph| ph.bars.between?(2, 4) })
      assert_equal piece.names.size, piece.phrases.sum(&:bars)
      assert_equal "authentic", piece.phrases.last.cadence
      piece.phrases.each_cons(2) { |a, b| assert_equal a.first_bar + a.bars, b.first_bar }
    end
  end

  def test_the_last_chord_is_the_tonic_and_the_pedal_has_the_root_on_the_strong_beats
    organ_pieces(1..15).each do |piece|
      tonic_pc = piece.pcs.first
      assert_equal tonic_pc, Chords.parse(piece.names.last)[:pc]
      pedal = piece.lines.fetch("pedal")
      assert_equal tonic_pc, pedal.last.midi % 12, "it ends on the tonic"
      piece.names.each_index { |bar| assert(pedal.any? { |n| n.step <= bar * 16 && bar * 16 < n.step + n.length }, "the pedal sounds on the downbeat of bar #{bar}") }
      strong = pedal.select { |n| (n.step % 16).zero? }
      roots = strong.count { |n| n.midi % 12 == Chords.parse(piece.names[n.step / 16])[:pc] }
      assert_operator roots, :>=, strong.size * 0.6, "mostly the chord's root; some bars hold the third under a suspension"
    end
  end

  def test_suspensions_tie_the_note_over_and_fall_a_step_on_the_third_beat
    found = 0
    organ_pieces(1..20).each do |piece|
      left = piece.lines.fetch("left")
      piece.suspensions.times { found += 1 }
      next if piece.suspensions.zero?

      # a note that crosses a barline and then drops by a scale step on the third beat
      ties = left.select { |n| ((n.step % 16) + n.length) > 16 && n.step % 16 >= 2 }
      ties.each do |n|
        bar_end = ((n.step / 16) + 1) * 16
        fall = left.any? { |m| m.step == bar_end + 8 && (m.midi - n.midi).between?(-3, -1) } # three semitones where the scale has its augmented second
        assert fall, "a tie at step #{n.step} resolves down a step at #{bar_end + 8}"
      end
    end
    assert_operator found, :>, 20, "suspensions occur across the pieces"
  end

  def test_the_suspension_types_are_four_three_seven_six_and_nine_eight
    organ_pieces(1..25).each { |piece| assert_operator piece.suspensions, :<=, piece.names.size }
    assert_equal %w[4-3 7-6 9-8], Organ::SUSPENSION.keys.sort
    assert_equal %w[4-3 7-6 9-8], ORGAN.dig("suspensions", "types").sort
    Organ::SUSPENSION.each_value { |row| assert_equal 1, row[:held] - row[:resolved], "the held note falls a scale step" }
    assert_equal({ "4-3" => 0, "9-8" => 0, "7-6" => 2 }, Organ::SUSPENSION.transform_values { |row| row[:bass] }, "the first two sit over the root, the last over the third")
  end

  def test_the_right_hand_runs_in_stepwise_eighths_and_sixteenths_with_trills_and_dotted_rhythms
    runs = trills = dotted = 0
    organ_pieces(1..20).each do |piece|
      right = piece.lines.fetch("right")
      right.each_cons(2) do |a, b|
        next unless a.step + a.length == b.step && a.length <= 2 && b.length <= 2

        interval = (b.midi - a.midi).abs
        runs += 1 if interval.between?(1, 3)
      end
      right.each_cons(3) { |a, b, c| trills += 1 if a.length == 1 && b.length == 1 && a.midi == c.midi && (b.midi - a.midi).between?(1, 2) }
      dotted += right.each_cons(2).count { |a, b| a.length == 3 && b.length == 1 && a.step + 3 == b.step }
    end
    assert_operator runs, :>, 1000
    assert_operator trills, :>, 100
    assert_operator dotted, :>, 50
  end

  def test_the_right_hand_never_sounds_two_notes_at_once_and_breathes_at_a_phrase_end
    organ_pieces(1..8).each do |piece|
      right = piece.lines.fetch("right").sort_by(&:step)
      right.each_cons(2) { |a, b| assert_operator a.step + a.length, :<=, b.step }
      piece.phrases[0...-1].each do |phrase|
        landing = right.find { |n| n.step == phrase.last_bar * 16 }
        assert_equal 12, landing.length, "the last note lets go four sixteenths early"
      end
    end
  end

  def test_the_right_hand_registration_rotates_each_phrase_and_the_other_lines_keep_theirs
    piece = Organ.compose(seed: 4, config: ORGAN, bars: 24)
    names = piece.phrases.map(&:registration)
    assert_equal ORGAN.fetch("rotation").first(names.size), names.first(ORGAN.fetch("rotation").size)
    names.each_cons(2) { |a, b| refute_equal a, b }
    registrations = DATA.dig("voices", "organ", "registrations")
    ORGAN.fetch("rotation").each { |name| assert_includes registrations, name }
    ORGAN.fetch("lines").each_value { |name| assert_includes registrations, name }
  end

  def test_a_phrase_motif_comes_back_later_in_the_piece
    piece = Organ.compose(seed: 5, config: ORGAN, bars: 32)
    right = piece.lines.fetch("right")
    shapes = right.each_cons(4).map { |four| four.map(&:length) }
    repeats = shapes.tally.select { |shape, n| n >= 3 && shape.sum >= 6 }
    refute_empty repeats, "a rhythm of four notes returns"
  end

  def test_rubato_leans_the_notes_inside_the_clamp_and_into_the_cadence
    seq = sequencer("dry")
    piece = Organ.compose(seed: 3, config: ORGAN, bars: 8)
    phrase = piece.phrases.first
    leans = (0...(phrase.bars * 16)).map { |s| seq.rubato(s, phrase, ORGAN) }
    assert(leans.all? { |lean| lean.abs <= MAX_OFFSET })
    assert_operator leans.min, :<, 0.0, "ahead of the beat through the phrase"
    assert_operator leans.last, :>, 0.01, "behind it as the cadence closes"
    assert_operator leans.max, :<=, ORGAN.fetch("rubato_ms") / 1000.0
  end

  def test_the_organ_mode_renders_a_piece_of_the_asked_length
    Dir.mktmpdir do |dir|
      out = File.join(dir, "organ.wav")
      stdout, err, status = run_dilla("--mode", "organ", "--bars", "4", "--key", "D", "--scale", "harmonic_minor", "--seed", "2",
                                      "--profile", "dry", "--tape", "0", "--midi", File.join(dir, "o.mid"), "--out", out, chdir: dir)
      assert status.success?, err
      assert_includes stdout, "organ in D harmonic_minor"
      seconds = (File.size(out) - 44) / 2.0 / SAMPLE_RATE
      assert_operator seconds, :>=, (4 * 4 * 60.0 / 88) - 0.01
      assert_operator seconds, :<, (4 * 4 * 60.0 / 88) + 4.0
      assert_operator File.binread(out).byteslice(44..).unpack("s<*").map(&:abs).max, :>, 3000
      assert File.file?(File.join(dir, "o.mid"))
    end
  end

  def test_organ_is_one_of_the_play_modes_and_needs_no_patch_from_the_bag
    list = Playlist.new(DATA, Random.new(2))
    picks = Array.new(40) { list.draw(profile: "dry") }
    organ = picks.select { |pick| pick[:mode] == "organ" }
    refute_empty organ
    assert(organ.all? { |pick| pick[:voice] == "organ" && pick[:bag].nil? })
    assert_includes Playlist::MODES, "organ"
  end

  # ------------------------------------------------------------- fluid and creative arpeggios

  def flow_stream(seed: 5, names: %w[Abmaj7 Fm9 Dbmaj7 Eb7], beats: 8.0)
    seq = sequencer("dry", seed:)
    settings = seq.arp_settings(nil, style: "flow").merge("modifiers" => [])
    [seq.note_events(names, 88.0, beats, settings, "arp").flatten, seq]
  end

  def test_the_flow_arp_breathes_through_quarters_eighths_triplets_and_sixteenths
    gaps = Hash.new(0)
    (1..12).each do |seed|
      plucks, = flow_stream(seed:)
      step = 60.0 / 88.0 / 4.0
      plucks.each_cons(2) { |a, b| gaps[((b.base - a.base) / step).round(2)] += 1 if b.base > a.base }
    end
    [4.0, 2.0, 1.33, 1.0].each { |gap| assert_operator gaps[gap], :>, 0, "a gap of #{gap} sixteenths" }
  end

  def test_the_flow_arp_is_seeded_stays_on_the_chord_and_leans_inside_the_clamp
    a, = flow_stream(seed: 9)
    b, = flow_stream(seed: 9)
    assert_equal a.map(&:to_a), b.map(&:to_a)
    refute_equal a.map(&:midi), flow_stream(seed: 10).first.map(&:midi)
    assert(a.all? { |p| p.off.abs <= MAX_OFFSET })
    assert_operator a.map(&:off).min, :<, 0.0
    assert_operator a.map(&:off).max, :>, 0.0
    assert(a.all? { |p| p.gain.between?(0.05, 1.0) })
  end

  def test_the_flow_arp_swells_toward_its_top_notes_and_ghosts_the_notes_it_passes
    high = low = passing = other = []
    gains = []
    (1..6).each do |seed|
      plucks, = flow_stream(seed:)
      plucks.each_cons(3) do |a, b, c|
        (a.midi < b.midi && b.midi < c.midi) || (a.midi > b.midi && b.midi > c.midi) ? passing += [b.gain] : other += [b.gain]
      end
      mid = plucks.map(&:midi).minmax.sum / 2.0
      plucks.each { |p| (p.midi > mid ? high += [p.gain] : low += [p.gain]) }
      gains.concat(plucks.map(&:gain))
    end
    avg = ->(list) { list.sum / list.size }
    assert_operator avg.call(high), :>, avg.call(low), "louder as it climbs"
    assert_operator avg.call(passing), :<, avg.call(other) * 0.85, "passing notes are ghosted"
    assert_operator gains.max - gains.min, :>, 0.4, "a real range of velocity"
  end

  def test_the_energy_walk_stays_between_zero_and_one_and_a_pad_swells_with_it
    walk = Flow::Walk.new(3)
    values = Array.new(500) { |i| walk.step(0.5 + (0.4 * Math.sin(i / 20.0))) }
    assert(values.all? { |v| v.between?(0.0, 1.0) })
    assert_operator values.max - values.min, :>, 0.5
    swelled = Flow.swell(Array.new(200, 1.0), [1.0, 0.0], 100)
    assert_operator swelled.first, :>, swelled[99] * 0.0 + 0.9
    assert_operator swelled[99], :<, 0.35
  end

  def test_the_creative_patterns_have_their_shapes
    pool = [40, 52, 60, 67, 72]
    spiral = Arp.sequence("spiral", pool, 9, 1)
    assert_equal [60, 67, 52, 72, 40], spiral.first(5), "out from the middle, one either side in turn"
    pendulum = Arp.sequence("pendulum", pool, 8, 1)
    assert_equal [40, 60, 52, 67, 60, 72, 67], pendulum.first(7)
    assert_equal [52, 52, 60, 67, 40, 67, 67, 52], Arp.sequence("fibonacci", pool, 8, 1)
    walk = Arp.sequence("prime_walk", pool, 12, 1)
    assert_equal [60, 40, 40, 60], walk.first(4), "strides of 2, 3, 5, 7 round five notes"
    assert_operator walk.uniq.size, :>=, 3
    call = Arp.sequence("call_response", pool, 8, 1)
    assert_equal [40, 52, 60, 67], call.first(4), "the call rises"
    assert_operator call[4], :>, call[5], "the answer falls"
    assert_nil call.last, "and rests"
    point = Arp.sequence("pedal_point", pool, 8, 1)
    assert(point.each_slice(2).all? { |low, _| low == 40 }, "the pedal on every other note")
    assert_equal point.each_slice(2).map(&:last), [52, 60, 67, 72]
  end

  def test_the_polyrhythm_styles_run_five_and_seven_sixteenths_against_the_grid
    [["poly5", 5], ["poly7", 7]].each do |style, gap|
      seq = sequencer("dry", seed: 2)
      plucks = seq.note_events(%w[Cm9], 88.0, 8.0, seq.arp_settings(nil, style:).merge("modifiers" => []), "arp").first
      step = 60.0 / 88.0 / 4.0
      assert_equal [gap], plucks.each_cons(2).map { |a, b| ((b.base - a.base) / step).round }.uniq
      refute(plucks.all? { |p| ((p.base / step).round % 4).zero? }, "not all on the beat")
    end
  end

  def test_arp_list_names_the_patterns_and_styles
    Dir.mktmpdir do |dir|
      out, err, status = run_dilla("--arp", "list", chdir: dir)
      assert status.success?, err
      %w[spiral pendulum fibonacci prime_walk call_response pedal_point flow poly5 poly7].each { |name| assert_includes out, name }
    end
  end

  # ------------------------------------------------------------- streaming

  def stream_pass(options, block)
    streamer = Streamer.new(DATA, { mono: true }.merge(options))
    out = []
    out.concat(streamer.next_block(block)) until streamer.finished?
    [out, streamer]
  end

  def assert_blocks_equal_whole(options, block = 13_337, delta: 1e-9)
    whole, = stream_pass(options, 10_000_000)
    cut, = stream_pass(options, block)
    assert_equal whole.size, cut.size, options[:profile]
    assert_in_delta 0.0, whole.zip(cut).map { |a, b| (a - b).abs }.max, delta, "#{options[:profile]}: blocks change the sound"
    assert_operator Tape.rms(whole), :>, 0.001
  end

  def test_a_pass_cut_into_blocks_is_the_pass_in_one_block
    %w[arp_echo rhodes_sonitex techno_arp industrial_arp eclectic].each do |profile|
      assert_blocks_equal_whole({ prog: 3, seed: 5, beats: 1.0, profile: })
    end
    assert_blocks_equal_whole({ prog: 2, seed: 4, beats: 1.0, profile: "dub_dark" }, 44_100)
    assert_blocks_equal_whole({ prog: 2, seed: 4, beats: 1.0, profile: "dry", mode: "pad", voice: "moog_pad" }, 5000)
    assert_blocks_equal_whole({ seed: 3, mode: "organ", bars: 4, profile: "dry" }, 20_011)
    assert_blocks_equal_whole({ prog: 5, seed: 4, beats: 2.0, profile: "dry", mode: "arp", arp_style: "flow", voice: "rhodes_mark1", pad: true }, 9999)
  end

  def test_a_note_read_in_blocks_is_the_note_whole
    %w[moog_pad rhodes_mark1 dub_bubble organ pure_tone sine dfam].each do |name|
      spec = DATA.fetch("voices").fetch(name)
      registration = spec.dig("registrations", "full")
      whole = Voices.note(spec, 57, 0.4, 0.2, step: 0.1, registration:)
      reader = Voices.reader(spec, 57, 0.4, 0.2, step: 0.1, registration:)
      cut = []
      cut.concat(reader.read(1)) until reader.done? || cut.size > 100 # one at a time to begin, then bigger
      cut.concat(reader.read(777)) until reader.done?
      assert_equal whole, cut, name
      assert_empty reader.read(10)
    end
  end

  def test_each_processor_gives_the_same_samples_in_blocks_as_in_one_call
    rng = Random.new(1)
    signal = Array.new(30_000) { (rng.rand * 2) - 1 }
    blocks = ->(proc_class, *args) { proc_class.new(*args).then { |s| signal.each_slice(1777).flat_map { |b| s.process(b) } } }
    whole = ->(proc_class, *args) { proc_class.new(*args).process(signal) }
    [[Stream::Lowpass, 900.0], [Stream::Highpass, 120.0], [Stream::Compressor, -18.0, 3.0, 5.0, 80.0, 0.0], [Stream::Crush, 8, 2.5],
     [Stream::Vcs, 0.6], [Stream::Reverb, 0.5], [Stream::Spring, 0.4], [Stream::SmoothLowpass, 300.0],
     [Stream::Sonitex, DATA.dig("sonitex", "presets").values.first, 4]].each do |klass, *args|
      assert_equal whole.call(klass, *args), blocks.call(klass, *args), klass.name
    end
    echo = { delay: 0.01, heads: [1, 2, 3], intensity: 0.6, volume: 0.5, lowpass: 3000, saturation: 0.4, reverb: 0.3, resets: [9000] }
    assert_equal Stream::EchoLine.new(**echo).process(signal), signal.each_slice(1777).flat_map { |b| (@e ||= Stream::EchoLine.new(**echo)).process(b) }
  end

  def test_the_whole_render_functions_are_the_processors_run_once
    signal = Array.new(5000) { |i| Math.sin(i / 7.0) * 0.4 }
    assert_equal Stream::Lowpass.new(800.0).process(signal), FX.lowpass(signal, 800.0)
    assert_equal Stream::Highpass.new(90.0).process(signal), Colour.highpass(signal, 90.0)
    assert_same signal, FX.spring(signal, 0.0)
    assert_equal Stream::Spring.new(0.3).process(signal), FX.spring(signal, 0.3)
    echo = Echo.process(signal, delay: 0.01, heads: [1, 2], intensity: 0.5, volume: 0.4, lowpass: 3000, saturation: 0.2, tail: 0.5)
    line = Stream::EchoLine.new(delay: 0.01, heads: [1, 2], intensity: 0.5, volume: 0.4, lowpass: 3000, saturation: 0.2)
    assert_equal echo, line.process(signal + Array.new(22_050, 0.0))
  end

  def test_the_streamed_pass_is_about_as_loud_as_the_whole_render
    options = { prog: 3, seed: 5, beats: 2.0, profile: "arp_echo", tape: 0 }
    streamed, streamer = stream_pass(options, 30_000)
    whole = render(DATA, options.merge(buffer_only: true))
    assert_in_delta 0.0, Tape.db(Tape.rms(streamed.first(streamer.source_end)) / Tape.rms(whole.first(streamer.source_end))), 1.0
  end

  def test_the_source_fades_at_the_ends_and_a_dry_pass_goes_silent_after_it
    streamer = Streamer.new(DATA, { mono: true, prog: 3, seed: 5, beats: 1.0, profile: "dry", mode: "pad", voice: "moog_pad" }, fade_in: 4410, fade_out_beats: 1)
    out = []
    out.concat(streamer.next_block(20_000)) until streamer.finished?
    assert_in_delta 0.0, out.first.abs, 1e-3, "begins from silence"
    assert_equal streamer.source_end, out.size, "a dry pass has no tail"
    assert_operator out.last(50).map(&:abs).max, :<, 1e-3, "and ends in silence"
    assert_operator out[streamer.source_end - 2 * streamer.beat, 1000].map(&:abs).max, :>, 0.001
  end

  def test_the_bank_starts_a_note_inside_a_block_and_carries_it_across_the_next
    note = ->(v) { -> { Voices::Reader.of(Array.new(10, v)) } }
    bank = Stream::Bank.new([Stream::Bank::Entry.new(3, note.call(1.0), 1.0, nil), Stream::Bank::Entry.new(8, note.call(0.5), 2.0, nil)])
    assert_equal [0, 0, 0, 1, 1, 1], bank.block(0, 6).first
    assert_equal [1, 1, 2, 2, 2, 2], bank.block(6, 6).first
    refute bank.finished?
    bank.block(12, 20)
    assert bank.finished?
  end

  FakePlayer = Struct.new(:blocks, :open) do
    def write(samples)
      return false unless open != false

      blocks << samples
      true
    end

    def finish = nil
    def kill = nil
    def interrupt = nil
  end

  def show_with(passes, seed, **extra)
    player = FakePlayer.new([])
    options = { mono: true, passes:, seed:, beats: 1.0, profile: "dry", mode: "pad", voice: "moog_pad", tape: 0, decks: 1, out: File.join(Dir.mktmpdir, "x.wav") }.merge(extra)
    show = Show.new(DATA, options, player:, out: StringIO.new)
    show.run
    [show, player]
  end

  def test_live_pass_uses_and_reports_the_profile_kit_for_its_expanded_drum_pattern
    show, = show_with(1, 19, profile: "dilla_shadow")
    pick = {
      prog: 2, position: "1/4", mode: "pad", style: nil,
      voice: "rhodes_mark1", voices: nil, profile: "dilla_shadow",
      kit: "kit_world", drums: "boom_bap", bag: nil
    }

    pass = show.send(:pass_options, pick, 1)

    assert_equal "dilla_shadow_full", pass[:drums]
    assert_equal "kit_dust", pass[:kit]
  end

  def test_the_show_starts_with_one_beat_then_plays_a_bar_at_a_time_and_joins_under_the_last_beat
    show, player = show_with(3, 6, beats: 4.0)
    first = show.streamers.first
    assert_equal first.beat, player.blocks.first.size, "one beat first"
    assert_equal 3 * first.beat, player.blocks[1].size, "the rest of the bar"
    assert_equal 4 * first.beat, player.blocks[2].size, "then a bar at a time"
    assert_equal 3, show.streamers.size
    assert_equal first.source_end - first.beat, show.joins[1], "the next pass begins one beat before the last ends"
    second = show.streamers[1]
    assert_equal show.joins[1] + second.source_end - second.beat, show.joins[2]
    assert_operator player.blocks.sum(&:size), :>=, show.joins.last + show.streamers.last.source_end
  end

  def test_there_is_no_click_at_a_join
    show, player = show_with(2, 3)
    samples = player.blocks.flatten
    join = show.joins[1]
    steps = samples.each_cons(2).map { |a, b| (b - a).abs }
    around = steps[join - 4410, 8820].max
    rest = steps.reject.with_index { |_, i| i.between?(join - 4410, join + 4410) }.sort[-1]
    assert_operator around, :<=, [rest * 1.5, 0.05].max, "no step at the join is bigger than any other in the pass"
    assert_operator Tape.rms(samples[join - 2000, 4000]), :>, 0.005, "and it does not dip to silence"
  end

  def test_the_master_stage_runs_once_over_the_sum_and_stays_under_the_ceiling
    _show, player = show_with(2, 3, tape: 2)
    samples = player.blocks.flatten
    assert_operator samples.map(&:abs).max, :<=, 0.97 + 1e-9
    assert_operator Tape.rms(samples), :>, 0.01
  end

  def test_a_player_that_has_gone_ends_the_show_quietly
    player = FakePlayer.new([], false)
    show = Show.new(DATA, { mono: true, passes: 5, seed: 1, beats: 1.0, profile: "dry", mode: "pad", voice: "moog_pad", tape: 0, decks: 1, out: File.join(Dir.mktmpdir, "x.wav") },
                    player:, out: StringIO.new)
    Timeout.timeout(60) { show.run }
    assert_empty player.blocks
  end

  def test_a_real_closed_pipe_is_not_an_error
    Dir.mktmpdir do |dir|
      player = Player.new(["sh", "-c", "exit 0"])
      sleep 0.3
      results = Array.new(40) { player.write(Array.new(44_100, 0.1)) }
      refute results.last, "write reports false once the reader is gone"
      player.finish
      assert_equal "\x00\x00".b, Player.pcm([0.0]).b
      assert_equal [32_767, -32_768], Player.pcm([2.0, -2.0]).unpack("s<*")
    end
  end

  def test_a_signal_ends_a_play_run_cleanly_and_takes_the_player_with_it
    Dir.mktmpdir do |dir|
      marker = "sleep 97.#{Process.pid % 1000}"
      pid = Process.spawn(RbConfig.ruby, SCRIPT, "--mono", "--play", "--player", marker, "--seed", "4", "--beats", "1", "--profile", "dry",
                          "--mode", "pad", "--tape", "0", "--decks", "1", "--out", File.join(dir, "x.wav"), chdir: dir, out: File.join(dir, "out.txt"), err: File::NULL)
      sleep 6
      Process.kill("TERM", pid)
      status = Timeout.timeout(30) { Process.wait2(pid).last }
      assert status.exited? && status.success?, "it ends by itself and well: #{status.inspect}"
      sleep 0.5
      assert_empty Open3.capture2("pgrep", "-f", marker).first.strip, "the player did not outlive the show"
    end
  end

  # ------------------------------------------------------------- the two-deck mixer and the live moves

  FakeDeck = Struct.new(:echo_boost, :drums_gain)

  def fresh_decks = [FakeDeck.new(1.0, 1.0), FakeDeck.new(1.0, 1.0)]

  # Walk a hand through `minutes` of bars at 88 beats a minute and return what it did.
  def walk_hand(seed, per_minute, minutes, overlap: ->(_bar) { false })
    hand = Moves::Hand.new(seed, per_minute:)
    decks = fresh_decks
    bar = (4 * 60.0 / 88 * SAMPLE_RATE).round
    seen = []
    ((minutes * 60.0 * SAMPLE_RATE) / bar).to_i.times do |i|
      params = hand.advance(i * bar, bar, bar, decks, overlap: overlap.call(i))
      seen << [i, hand.current&.fetch(:name), params, decks.map(&:to_a)]
    end
    hand.stop(decks)
    [hand, decks, seen]
  end

  def test_moves_come_a_few_a_minute_all_six_kinds_none_twice_running_and_are_logged
    hand, decks, = walk_hand(7, 3.0, 40)
    names = hand.log.map(&:first)
    assert_equal Moves::NAMES.sort, names.uniq.sort
    names.each_cons(2) { |a, b| refute_equal a, b }
    rate = names.size / 40.0
    assert_operator rate, :>=, 1.0
    assert_operator rate, :<=, 4.0
    assert_equal [[1.0, 1.0]] * 2, decks.map(&:to_a), "every moved parameter is put back"
    hand.log.each_cons(2) do |(_, start, bars), (_, next_start, _)|
      assert_operator next_start - (start + (bars * 4 * 60.0 / 88 * SAMPLE_RATE)), :>=, Moves::GAP_SECONDS * SAMPLE_RATE - 4, "a gap between moves"
    end
  end

  def test_moves_are_seeded_start_on_bar_lines_and_never_while_two_decks_cross
    a, = walk_hand(3, 4.0, 20)
    b, = walk_hand(3, 4.0, 20)
    c, = walk_hand(4, 4.0, 20)
    assert_equal a.log, b.log
    refute_equal a.log, c.log
    bar = (4 * 60.0 / 88 * SAMPLE_RATE).round
    assert(a.log.all? { |_, start, _| (start % bar).zero? })
    crossing = ->(i) { (i % 10) >= 6 }
    hand, = walk_hand(5, 30.0, 10, overlap: crossing)
    assert(hand.log.none? { |_, start, _| crossing.call(start / bar) }, "no move begins inside a crossfade")
    quiet, = walk_hand(5, 0.0, 10)
    assert_empty quiet.log
  end

  def test_each_move_changes_its_parameter_and_gives_it_back
    hand = Moves::Hand.new(1, per_minute: 0.0)
    cut = ->(name, bars) { hand.instance_variable_set(:@current, { name:, start: 0, length: bars * 1000, bars: }) }
    cut.call("filter_sweep", 3)
    first, = hand.send(:params, 0.0, 0.01, [])[:cutoff]
    mid = hand.send(:params, 0.45, 0.5, [])[:cutoff].first
    last = hand.send(:params, 0.99, 1.0, [])[:cutoff].last
    assert_in_delta Moves::TOP_HZ, first, 200
    assert_in_delta Moves::LOW_HZ, mid, 1
    assert_in_delta Moves::TOP_HZ, last, 200
    cut.call("tape_ramp", 3)
    assert_in_delta 2.0, hand.send(:params, 0.45, 0.55, [])[:tape], 1e-9
    assert_operator hand.send(:params, 0.0, 0.02, [])[:tape], :<, 1.1
    cut.call("sonitex_climb", 5)
    assert_equal [1, 2, 3, 2, 1], [0.0, 0.2, 0.4, 0.6, 0.8].map { |p| hand.send(:params, p, p + 0.1, [])[:sonitex] }
    cut.call("reverb_swell", 3)
    assert_equal [0.0, 0.0], hand.send(:params, 0.0, 0.0, [])[:room].map { |v| v.round(6) }
    assert_in_delta Moves::ROOM_LEVEL, hand.send(:params, 0.4, 0.5, [])[:room].last, 1e-9
    assert_in_delta 0.0, hand.send(:params, 1.0, 1.0, [])[:room].last, 1e-9
  end

  def test_the_master_stage_does_nothing_unless_asked_and_a_sweep_darkens_it
    rng = Random.new(2)
    noise = Array.new(20_000) { ((rng.rand * 2) - 1) * 0.3 }
    preset = DATA.dig("sonitex", "presets").values.first
    master = Moves::Master.new(tape: nil, ceiling: 0.97, preset:, seed: 1)
    assert_equal [noise], master.process([noise])
    dark = master.process([noise], cutoff: [700.0, 700.0]).first
    high = ->(buf) { Tape.rms(Colour.highpass(buf, 6000.0)) }
    assert_operator Tape.db(high.call(dark) / high.call(noise)), :<, -20.0
    wet = Moves::Master.new(tape: nil, ceiling: 0.97, preset:, seed: 1)
    refute_equal [noise], wet.process([noise], sonitex: 3)
    refute_equal [noise], wet.process([noise], room: [0.4, 0.4])
    stack = Tape::Stack.new(instances: 2, seed: 1, config: DATA.fetch("tape"))
    taped = Moves::Master.new(tape: stack, ceiling: 0.97, preset:, seed: 1)
    taped.process([noise], tape: 2.0)
    assert_equal [2.0, 2.0], stack.machines.map(&:scale)
    taped.process([noise])
    assert_equal [1.0, 1.0], stack.machines.map(&:scale), "the drive goes back when the move ends"
  end

  def test_a_prefetched_deck_gives_the_same_samples_and_the_live_controls_act
    options = { prog: 3, seed: 5, beats: 1.0, profile: "eclectic", tape: 0 }
    plain, = stream_pass(options, 20_000)
    ahead = Streamer.new(DATA, options.merge(mono: true))
    ahead.prefetch(50_000)
    out = []
    out.concat(ahead.next_block(20_000)) until ahead.finished?
    assert_equal plain, out
    muted = Streamer.new(DATA, options.merge(mono: true))
    muted.drums_gain = 0.0
    quiet = []
    quiet.concat(muted.next_block(20_000)) until muted.finished?
    assert_operator Tape.rms(quiet), :<, Tape.rms(plain) * 0.7, "a dropout takes the drums out"
    thrown = Streamer.new(DATA, options.merge(profile: "arp_echo", mono: true))
    thrown.echo_boost = 3.0
    base, = stream_pass(options.merge(profile: "arp_echo"), 20_000)
    loud = []
    loud.concat(thrown.next_block(20_000)) until thrown.finished?
    assert_operator Tape.rms(loud), :>, Tape.rms(base), "a throw turns the echo up"
    assert_equal 1.0, Streamer.new(DATA, options).echo_boost
  end

  def two_deck_show(passes, seed, **extra)
    player = FakePlayer.new([])
    options = { mono: true, passes:, seed:, profile: "eclectic", mode: "pad", voice: "pure_tone", tape: 0, decks: 2, moves: 0,
                out: File.join(Dir.mktmpdir, "x.wav") }.merge(extra)
    show = Show.new(DATA, options, player:, out: StringIO.new)
    show.run
    [show, player]
  end

  def test_two_decks_play_eight_to_sixteen_bars_and_cross_over_two_to_four_on_the_bar_line
    show, player = two_deck_show(3, 9)
    assert_equal 3, show.streamers.size
    show.streamers.each do |deck|
      bars = deck.source_end.to_f / (4 * deck.beat)
      assert_operator bars, :>=, 7.9
      assert_operator bars, :<=, 16.1
    end
    assert_equal 3, show.crossfades.size
    assert(show.crossfades.all? { |beats| [8, 12, 16].include?(beats) }, "two to four bars: #{show.crossfades}")
    show.streamers.each_cons(2).with_index do |(a, b), i|
      assert_equal show.joins[i] + a.source_end - a.fade_out, show.joins[i + 1]
      assert_operator ((a.source_end - a.fade_out) % (4 * a.beat)).then { |r| [r, 4 * a.beat - r].min }, :<=, 1, "on A's bar line"
      assert_operator (a.plan.bpm - b.plan.bpm).abs, :<=, Show::TEMPO_WINDOW + 1e-9, "tempo within six beats a minute"
      assert_equal a.fade_out, b.instance_variable_get(:@fade_in), "the same length out and in"
    end
    samples = player.blocks.flatten
    assert_operator samples.size, :>=, show.joins.last + show.streamers.last.source_end
    quiet = (0...((show.joins.last + show.streamers.last.source_end) / 22_050 - 1)).count { |i| Tape.rms(samples[i * 22_050, 22_050]) < 0.003 }
    assert_equal 0, quiet, "the music never drops out, the drums run on through every join"
  end

  def test_live_moves_run_inside_a_show_are_logged_and_leave_every_deck_as_it_was
    show, = two_deck_show(2, 13, moves: 40.0)
    refute_empty show.hand.log
    assert_equal [1.0], show.streamers.map(&:echo_boost).uniq
    assert_equal [1.0], show.streamers.map(&:drums_gain).uniq
    again, = two_deck_show(2, 13, moves: 40.0)
    assert_equal show.hand.log, again.hand.log
  end

  # ------------------------------------------------------------- the stereo bus

  def corr(a, b)
    ma = a.sum / a.size
    mb = b.sum / b.size
    num = a.zip(b).sum { |x, y| (x - ma) * (y - mb) }
    num / Math.sqrt(a.sum { |x| (x - ma)**2 } * b.sum { |y| (y - mb)**2 })
  end

  def test_the_pan_law_is_constant_power_and_unity_at_the_centre
    assert_equal [1.0, 1.0], Stereo.gains(0.0).map { |g| g.round(9) }
    [-1.0, -0.4, 0.3, 1.0].each do |pan|
      left, right = Stereo.gains(pan)
      assert_in_delta 2.0, (left**2) + (right**2), 1e-9
    end
    assert_operator Stereo.gains(-1.0).first, :>, Stereo.gains(-1.0).last
    assert_in_delta 0.0, Stereo.gains(-1.0).last, 1e-9
  end

  def test_the_data_places_each_voice_group_and_each_drum_role_and_every_group_has_a_place
    stereo = DATA.fetch("stereo")
    DATA.fetch("voices").each_value { |voice| assert stereo.fetch("groups").key?(voice.fetch("group")), voice["group"] }
    assert_equal 0.0, stereo.dig("drums", "kick")
    assert_operator stereo.dig("drums", "hat"), :>, 0.0
    assert(stereo.fetch("groups").values.all? { |pan| pan.abs <= 1.0 })
    assert_operator stereo.fetch("spread"), :<=, 1.0
  end

  def stereo_pass(options, block = 40_000)
    streamer = Streamer.new(DATA, options)
    frame = Stereo.zeros(2, 0)
    Stereo.concat!(frame, streamer.next_block(block)) until streamer.finished?
    [frame, streamer]
  end

  def test_a_stereo_pass_in_blocks_is_the_pass_in_one_and_the_channels_differ
    options = { prog: 3, seed: 5, beats: 1.0, profile: "arp_echo", mode: "arp", voice: "rhodes_mark1" }
    whole, = stereo_pass(options, 10_000_000)
    cut, streamer = stereo_pass(options, 13_337)
    assert_equal 2, streamer.channels
    assert_equal whole.map(&:size), cut.map(&:size)
    assert_in_delta 0.0, whole.flatten.zip(cut.flatten).map { |a, b| (a - b).abs }.max, 1e-9
    refute_equal whole[0], whole[1]
    assert_operator corr(whole[0], whole[1]), :<, 0.97, "two channels, not a doubled one"
    assert_operator corr(whole[0], whole[1]), :>, 0.2, "but one band"
  end

  def test_a_voice_group_sits_where_the_data_puts_it
    pure = stereo_pass({ prog: 3, seed: 5, beats: 1.0, profile: "dry", mode: "pad", voice: "pure_tone" }).first
    moog = stereo_pass({ prog: 3, seed: 5, beats: 1.0, profile: "dry", mode: "pad", voice: "moog_pad" }).first
    assert_operator Tape.rms(pure[1]), :>, Tape.rms(pure[0]), "pure_tone sits right of the middle"
    assert_operator Tape.rms(moog[0]), :>, Tape.rms(moog[1]), "the moogs sit left"
    centred = stereo_pass({ prog: 3, seed: 5, beats: 1.0, profile: "dry", mode: "pad", voice: "organ" }).first
    assert_in_delta 0.0, Tape.db(Tape.rms(centred[0]) / Tape.rms(centred[1])), 3.0
  end

  def test_the_drums_are_placed_by_role_and_the_kick_stays_in_the_middle
    frame, streamer = stereo_pass({ prog: 3, seed: 5, beats: 1.0, profile: "eclectic", mode: "pad", voice: "pure_tone" })
    kicks = streamer.hits.select { |role, _| role == "kick" }.first(4)
    refute_empty kicks
    kicks.each do |_, time, _|
      at = (time * SAMPLE_RATE).to_i
      window = [frame[0][at, 600], frame[1][at, 600]]
      assert_in_delta 0.0, Tape.db(Tape.rms(window[0]) / Tape.rms(window[1])), 3.0
    end
  end

  def test_the_ping_pong_echo_puts_the_first_head_left_the_second_right_and_one_head_in_the_middle
    delay = 0.01
    d = (delay * SAMPLE_RATE).round
    input = [impulse(4000).map { |x| x * 0.05 }] * 2
    echo = Stream::PingPongEcho.new(delay:, heads: [1, 2], intensity: 0.0, volume: 1.0, lowpass: nil, saturation: 0.0)
    left, right = echo.process(input)
    assert_operator left[d].abs, :>, 1e-4
    assert_in_delta 0.0, right[d], 1e-9, "the first head is on the left"
    assert_operator right[2 * d].abs, :>, 1e-4
    assert_in_delta 0.0, left[2 * d], 1e-9, "the second on the right"
    one = Stream::PingPongEcho.new(delay:, heads: [1], intensity: 0.0, volume: 1.0, lowpass: nil, saturation: 0.0).process(input)
    assert_equal one[0], one[1], "a single head is heard in the middle"
    blocks = Stream::PingPongEcho.new(delay:, heads: [1, 2, 3], intensity: 0.6, volume: 0.5, lowpass: 3000, saturation: 0.3, reverb: 0.2)
    whole = Stream::PingPongEcho.new(delay:, heads: [1, 2, 3], intensity: 0.6, volume: 0.5, lowpass: 3000, saturation: 0.3, reverb: 0.2)
    signal = [Array.new(9000) { |i| Math.sin(i / 9.0) * 0.2 }] * 2
    cut = signal.map { |ch| ch.each_slice(1500).to_a }
    parts = cut[0].each_index.map { |k| blocks.process([cut[0][k], cut[1][k]]) }
    assert_equal whole.process(signal), [parts.flat_map(&:first), parts.flat_map(&:last)]
  end

  def test_the_right_room_is_not_the_left_room
    impulse_block = impulse(30_000)
    left = Stream::Reverb.new(0.6).process(impulse_block)
    right = Stream::Reverb.new(0.6, side: :right).process(impulse_block)
    refute_equal left, right
    assert_operator corr(left[1000..], right[1000..]).abs, :<, 0.3, "decorrelated"
    spring_left = Stream::Spring.new(0.5).process(impulse_block)
    spring_right = Stream::Spring.new(0.5, side: :right).process(impulse_block)
    refute_equal spring_left, spring_right
  end

  def test_the_imager_centres_the_lows_widens_the_highs_and_leaves_the_mid_alone
    sine = ->(hz, phase = 0) { Array.new(SAMPLE_RATE) { |i| 0.3 * Math.sin((2 * Math::PI * hz * i / SAMPLE_RATE) + phase) } }
    mono_in = sine.call(1000)
    imager = Stream::Imager.new
    out = imager.process([mono_in, mono_in])
    assert_equal out[0], out[1], "a mono signal stays mono"
    low = sine.call(60)
    out = Stream::Imager.new.process([low, low.map(&:-@)]) # all side
    assert_operator Tape.db(Tape.rms(out[0].last(20_000)) / Tape.rms(low)), :<, -20.0, "the side below 120 Hz is taken out of the sub"
    high_l = sine.call(8000)
    high_r = sine.call(8000, 1.0)
    before = Stereo.mid_side([high_l, high_r])
    after = Stereo.mid_side(Stream::Imager.new.process([high_l, high_r]))
    assert_operator Tape.rms(after[1].last(20_000)), :>, Tape.rms(before[1].last(20_000)) * 1.2, "the highs are wider"
    mid_before = Tape.rms(before[0].last(20_000))
    assert_in_delta 0.0, Tape.db(Tape.rms(after[0].last(20_000)) / mid_before), 0.5, "the mono sum keeps its level"
    assert_equal [1], Stream::Imager.new.process([mono_in]).map { 1 }
  end

  def test_a_stereo_wav_has_two_channels_and_interleaves_left_then_right
    Dir.mktmpdir do |dir|
      path = File.join(dir, "s.wav")
      WAV.write(path, [[0.5, 0.25], [-0.5, -0.25]])
      bytes = File.binread(path)
      assert_equal 2, bytes.byteslice(22, 2).unpack1("v")
      assert_equal SAMPLE_RATE * 4, bytes.byteslice(28, 4).unpack1("V")
      assert_equal 4, bytes.byteslice(32, 2).unpack1("v")
      assert_equal [16_384, -16_384, 8192, -8192], bytes.byteslice(44..).unpack("s<*")
      assert_equal [16_384, -16_384, 8192, -8192], Player.pcm([[0.5, 0.25], [-0.5, -0.25]]).unpack("s<*")
    end
  end

  def test_the_command_line_renders_stereo_by_default_and_mono_when_asked
    Dir.mktmpdir do |dir|
      args = ["--progression", "2", "--profile", "arp_echo", "--beats", "1", "--seed", "3", "--tape", "1"]
      _o, err, status = run_dilla(*args, "--out", File.join(dir, "s.wav"), chdir: dir, stereo: true)
      assert status.success?, err
      _o, err, status = run_dilla(*args, "--out", File.join(dir, "m.wav"), chdir: dir)
      assert status.success?, err
      stereo = File.binread(File.join(dir, "s.wav"))
      mono = File.binread(File.join(dir, "m.wav"))
      assert_equal [2, 1], [stereo.byteslice(22, 2).unpack1("v"), mono.byteslice(22, 2).unpack1("v")]
      pairs = stereo.byteslice(44..).unpack("s<*").each_slice(2).to_a
      assert_equal (mono.bytesize - 44) / 2, pairs.size, "the same length in frames"
      refute(pairs.all? { |l, r| l == r })
      again = File.join(dir, "s2.wav")
      run_dilla(*args, "--out", again, chdir: dir, stereo: true)
      assert_equal stereo, File.binread(again), "deterministic"
    end
  end

  def test_the_stereo_master_taps_the_mid_and_keeps_the_ceiling_in_both_channels
    stack = Tape::Stack.new(instances: 2, seed: 1, config: DATA.fetch("tape"))
    master = Moves::Master.new(tape: stack, ceiling: 0.97, preset: nil, seed: 1, instances: 2, tape_args: { drive: 1.0, config: DATA.fetch("tape") },
                               imager: DATA.dig("stereo", "imager"))
    rng = Random.new(5)
    loud = [Array.new(20_000) { ((rng.rand * 2) - 1) * 2.0 }, Array.new(20_000) { ((rng.rand * 2) - 1) * 2.0 }]
    out = master.process(loud)
    assert_equal 2, out.size
    assert_operator out.flatten.map(&:abs).max, :<=, 0.97 + 1e-9
  end

  # ------------------------------------------------------------- effect stages, noise and sparkle

  def tone(hz, seconds = 1.0, amp = 0.3, phase = 0.0) = Array.new((seconds * SAMPLE_RATE).round) { |i| amp * Math.sin((2 * Math::PI * hz * i / SAMPLE_RATE) + phase) }

  def stage(name, **over) = Stages.build({ "stage" => name }.merge(over.transform_keys(&:to_s)), DATA.fetch("stages"), channels: 1, seed: 7, end_sample: 40_000, bar_samples: 30_000)

  def test_every_stage_in_the_data_builds_and_every_profile_chain_names_real_stages
    DATA.fetch("stages").each_key { |name| assert_kind_of Stages::Chained, stage(name) }
    assert_equal DATA.fetch("stages").keys.sort, Stages::KINDS.keys.sort
    DATA.fetch("groove_profiles").each do |profile, row|
      Array(row["chain"]).each { |item| assert_includes DATA.fetch("stages"), item.is_a?(String) ? item : item.fetch("stage"), profile }
      (row["noise"] || {}).each_key { |layer| assert_includes DATA.fetch("noise"), layer, profile }
    end
    assert_raises(ArgumentError) { Stages.build("nonesuch", DATA.fetch("stages"), channels: 1, seed: 1) }
  end

  def test_every_stage_gives_the_same_samples_in_blocks_as_in_one_call_and_stays_finite
    rng = Random.new(3)
    signal = Array.new(60_000) { |i| (Math.sin(i / 9.0) * 0.2) + ((rng.rand - 0.5) * 0.05) }
    DATA.fetch("stages").each_key do |name|
      whole = stage(name).process([signal], 0).first
      cut = stage(name)
      parts = signal.each_slice(7001).with_index.flat_map { |chunk, k| cut.process([chunk], k * 7001).first }
      assert(whole.all?(&:finite?), name)
      assert_in_delta 0.0, whole.zip(parts).map { |a, b| (a - b).abs }.max, 1e-9, "#{name}: blocks change the sound"
      assert_operator whole.map(&:abs).max, :<, 4.0, name
    end
  end

  def test_the_pitch_shifter_takes_a_tone_up_an_octave
    pitch = Stages::Pitch.new(2.0)
    out = tone(440.0, 1.0).map { |x| pitch.step(x) }.last(20_000)
    crossings = out.each_cons(2).count { |a, b| a.negative? != b.negative? }
    assert_in_delta 880.0, crossings / 2.0 / (out.size.to_f / SAMPLE_RATE), 40.0
    assert_operator Tape.rms(out), :>, 0.1
  end

  def test_the_shimmer_rings_on_an_octave_above_the_note_and_the_plate_is_a_room
    burst = tone(440.0, 0.3) + Array.new(SAMPLE_RATE * 2, 0.0)
    shimmer = stage("shimmer", mix: 1.0, feedback: 0.5).process([burst]).first
    tail = shimmer[SAMPLE_RATE, SAMPLE_RATE]
    assert_operator Tape.rms(tail), :>, 0.004, "it rings after the note"
    plate = stage("plate", mix: 1.0).process([burst]).first
    assert_operator Tape.rms(plate[SAMPLE_RATE, SAMPLE_RATE]), :>, 0.001
    left = Stages.build({ "stage" => "plate" }, DATA.fetch("stages"), channels: 2, seed: 7).process([burst, burst])
    refute_equal left[0], left[1], "the right room is another room"
  end

  def test_the_granular_cloud_goes_on_after_the_input_stops_and_follows_its_seed
    burst = tone(300.0, 0.5) + Array.new(SAMPLE_RATE * 2, 0.0)
    cloud = stage("granular", mix: 1.0).process([burst]).first
    assert_operator Tape.rms(cloud[SAMPLE_RATE, SAMPLE_RATE / 2]), :>, 0.001
    assert_equal cloud, stage("granular", mix: 1.0).process([burst]).first
    other = Stages.build({ "stage" => "granular", "mix" => 1.0 }, DATA.fetch("stages"), channels: 1, seed: 8).process([burst]).first
    refute_equal cloud, other
    assert_equal burst, stage("granular", mix: 0.0).process([burst]).first.each_with_index.map { |v, i| v - 0.0 + 0.0 * i }
  end

  def test_the_frequency_shifter_moves_a_partial_by_a_number_of_hertz_and_the_ring_modulator_makes_sidebands
    shifted = stage("freqshift", hz: 100.0, mix: 1.0).process([tone(1000.0)], 0).first.last(22_050)
    assert_operator Tape.goertzel(shifted, 1100.0), :>, 0.25
    assert_operator Tape.goertzel(shifted, 900.0), :<, 0.01
    assert_operator Tape.goertzel(shifted, 1000.0), :<, 0.01
    ring = stage("ringmod", hz: 200.0, mix: 1.0).process([tone(1000.0)], 0).first.last(22_050)
    assert_operator Tape.goertzel(ring, 800.0), :>, 0.05
    assert_operator Tape.goertzel(ring, 1200.0), :>, 0.05
    assert_operator Tape.goertzel(ring, 1000.0), :<, 0.02
  end

  def test_the_crusher_the_folder_and_the_exciter_make_what_they_say
    ramp = Array.new(2000) { |i| (i / 1000.0) - 1.0 }
    assert_operator stage("crush", bits: 4, factor: 1.0, mix: 1.0).process([ramp]).first.uniq.size, :<=, 17, "four bits: sixteen steps and the zero"
    folded = stage("folder", gain: 3.0, mix: 1.0).process([tone(200.0, 1.0, 0.9)]).first
    assert_operator folded.map(&:abs).max, :<=, 1.0 / 3.0 * 1.0001 + 1e-6
    assert_operator Tape.goertzel(folded.last(22_050), 600.0), :>, 0.01, "a fold makes a third harmonic"
    dull = tone(5000.0, 1.0, 0.3)
    bright = stage("exciter", mix: 1.0, hz: 4000.0, drive: 4.0).process([dull]).first
    assert_operator Tape.goertzel(bright.last(22_050), 15_000.0), :>, 0.003, "a third harmonic at 15 kHz that was not there"
    assert_operator Tape.goertzel(dull.last(22_050), 15_000.0), :<, 0.0005
  end

  def test_the_comb_bank_rings_at_inharmonic_partials
    gain = ->(hz) { Tape.rms(stage("comb_bank", hz: 300.0, mix: 1.0).process([tone(hz, 1.0)]).first.last(22_050)) / Tape.rms(tone(hz, 1.0)) }
    assert_operator gain.call(300.0 * 2.76), :>, 1.3, "a resonance at 2.76 times the base"
    assert_operator gain.call(300.0 * 2.0), :<, 1.1, "and none at the octave"
  end

  def test_the_reverse_echo_plays_the_last_segment_backwards_and_swelling
    segment = (SAMPLE_RATE * 0.2).round
    ramp_up = Array.new(segment) { |i| i.to_f / segment } # rising in
    stage_ = Stages.build({ "stage" => "reverse_echo", "seconds" => 0.2, "mix" => 1.0 }, DATA.fetch("stages"), channels: 1, seed: 1)
    out = stage_.process([ramp_up + Array.new(segment, 0.0)]).first
    second = out[segment, segment]
    assert_operator second.first(segment / 4).map(&:abs).max, :<, second.last(segment / 4).map(&:abs).max + 1e-9, "it swells in"
    heard = second.each_with_index.map { |v, i| v / ((i.to_f / segment)**2 + 1e-9) }[(segment * 0.2)...(segment * 0.8)]
    assert_operator heard.first, :>, heard.last, "and what it plays is the segment backwards: it falls"
  end

  def test_the_tape_stop_slows_the_read_to_nothing_before_the_pass_ends
    pass_end = 4 * SAMPLE_RATE
    stopper = Stages.build({ "stage" => "tapestop", "seconds" => 0.8 }, DATA.fetch("stages"), channels: 1, seed: 1, end_sample: pass_end)
    out = stopper.process([tone(440.0, 5.0)], 0).first
    assert_equal tone(440.0, 5.0).first(pass_end - 40_000), out.first(pass_end - 40_000), "untouched until the stop begins"
    early = out[pass_end - 35_000, 4000]
    late = out[pass_end - 6000, 4000]
    zc = ->(buf) { buf.each_cons(2).count { |a, b| a.negative? != b.negative? } }
    assert_operator zc.call(late), :<, zc.call(early) * 0.7, "the pitch falls"
    assert_in_delta 0.0, out[pass_end - 200, 200].map(&:abs).max, 0.01, "and it is gone"
  end

  def test_the_sweep_is_an_event_every_so_many_bars_and_the_transient_shaper_lifts_the_front_of_a_note
    sweep = Stages::Sweep.new({ "every_bars" => 4, "bars" => 1, "low_hz" => 400.0, "top_hz" => 16_000.0 }, 1, 0, bar_samples: 1000)
    cutoffs = [0, 500, 1000, 1500, 2000, 3000, 4000, 5000].map { |at| sweep.send(:cutoff, at) }
    assert_in_delta 16_000.0, cutoffs[0], 1
    assert_in_delta 400.0, cutoffs[2], 1
    assert_in_delta 16_000.0, cutoffs[4], 1
    assert_in_delta 16_000.0, cutoffs[5], 1, "held open between sweeps"
    note = Array.new(8000) { |i| (i < 4000 ? Math.sin(i / 5.0) : 0.0) * [1.0, 0.0].max }
    shaped = stage("transient", attack_db: 6.0, sustain_db: -6.0).process([note.each_with_index.map { |v, i| i < 4000 ? v * Math.exp(-i / 1500.0) : 0.0 }]).first
    plain = note.each_with_index.map { |v, i| i < 4000 ? v * Math.exp(-i / 1500.0) : 0.0 }
    assert_operator shaped.first(300).map(&:abs).max, :>=, plain.first(300).map(&:abs).max * 0.999
  end

  def test_the_noise_layers_are_filtered_noise_kept_far_down_and_the_same_every_time
    air = Noise::Air.new(DATA.dig("noise", "air"), 4).block(44_100)
    assert_equal air, Noise::Air.new(DATA.dig("noise", "air"), 4).block(44_100)
    assert_operator Tape.rms(Colour.highpass(air, 8000.0)), :>, Tape.rms(air) * 0.5
    assert_operator Tape.db(Tape.rms(air)), :<, -45.0
    bed = Noise::Bed.new(DATA.dig("noise", "bed"), 4).block(88_200)
    assert_operator Tape.db(Tape.rms(bed)), :<, -42.0
    assert_operator Tape.rms(FX.lowpass(bed, 400.0)), :>, Tape.rms(bed) * 0.8, "under 200 hertz"
    assert_operator bed.map(&:abs).max, :<=, 0.05, "no spike"
    blocks = Noise::Bed.new(DATA.dig("noise", "bed"), 4)
    assert_equal bed, [blocks.block(30_000), blocks.block(58_200)].flatten
    assert_equal(-24.0, 20 * Math.log10(Noise.gain(0.0)).round(1))
  end

  def test_dust_is_a_sparse_poisson_scatter_and_sparkle_sits_on_the_chord_between_four_and_eight_kilohertz
    dust = Noise.dust({ "rate" => 6.0, "db" => -40.0 }, 11, 100.0)
    assert_in_delta 600, dust.size, 90
    assert_equal dust.map(&:start), Noise.dust({ "rate" => 6.0, "db" => -40.0 }, 11, 100.0).map(&:start)
    pcs = [0, 4, 7]
    glints = Noise.sparkle({ "rate" => 4.0, "db" => -30.0 }, 5, 60.0, ->(_t) { pcs })
    assert_in_delta 240, glints.size, 50
    sample = glints.first(40).map { |entry| entry.make.call.drain }
    sample.each do |samples|
      assert_operator samples.map(&:abs).max, :<=, Noise.gain(-30.0) * 1.001
      spectrum = (4000..8000).step(250).map { |hz| Tape.goertzel(samples, hz) }
      assert_operator spectrum.max, :>, 0
    end
    frequencies = pcs.flat_map { |pc| (108..119).select { |n| n % 12 == pc }.map { |n| Chords.hz(n) } }
    assert(frequencies.all? { |f| f.between?(4000, 8000) })
    assert_operator Noise.pop(Random.new(1), -10.0).map(&:abs).max, :<=, Noise.gain(-10.0) * 1.31
  end

  def test_the_new_profiles_render_stereo_in_blocks_the_same_as_whole
    %w[new_age tape_dust broken_radio].each do |profile|
      options = { prog: 3, seed: 5, beats: 1.0, profile: }
      whole, = stereo_pass(options, 10_000_000)
      cut, = stereo_pass(options, 11_111)
      assert_in_delta 0.0, whole.flatten.zip(cut.flatten).map { |a, b| (a - b).abs }.max, 1e-9, profile
      assert_operator Tape.rms(whole[0]), :>, 0.003, profile
    end
  end

  # ------------------------------------------------------------- mixing and mastering

  MASTER = DATA.fetch("master")

  def test_a_997_hz_sine_at_minus_20_dbfs_in_both_channels_is_minus_20_lufs
    sine = Array.new(SAMPLE_RATE * 6) { |i| 0.1 * Math.sin(2 * Math::PI * 997 * i / SAMPLE_RATE) }
    assert_in_delta(-20.0, Mastering::Loudness.integrated([sine, sine]), 0.2)
    assert_in_delta(-23.0, Mastering::Loudness.integrated([sine]), 0.2, "one channel alone is three decibels lower")
    quiet = sine.map { |v| v * 0.1 }
    assert_in_delta(-40.0, Mastering::Loudness.integrated([quiet, quiet]), 0.2)
  end

  def test_gating_ignores_silence_and_loudness_is_the_same_in_blocks
    sine = Array.new(SAMPLE_RATE * 4) { |i| 0.1 * Math.sin(2 * Math::PI * 997 * i / SAMPLE_RATE) }
    padded = [sine + Array.new(SAMPLE_RATE * 4, 0.0)] * 2
    assert_in_delta(-20.0, Mastering::Loudness.integrated(padded), 0.3, "the silence is gated out")
    meter = Mastering::Loudness::Meter.new(1)
    sine.each_slice(5003) { |part| meter.feed([part]) }
    assert_in_delta Mastering::Loudness.integrated([sine]), meter.integrated, 0.05
    assert_equal(-Float::INFINITY, Mastering::Loudness::Meter.new(1).integrated)
  end

  def reference_true_peak(samples)
    up = 16
    half = 24
    best = 0.0
    (half...(samples.size - half)).each do |i|
      (0...up).each do |k|
        offset = k.to_f / up
        sum = (-half + 1..half).sum do |j|
          at = i + j
          x = j - offset
          sinc = x.zero? ? 1.0 : Math.sin(Math::PI * x) / (Math::PI * x)
          samples[at] * sinc * (0.5 + (0.5 * Math.cos(Math::PI * x / (half + 1))))
        end
        best = sum.abs if sum.abs > best
      end
    end
    best
  end

  def test_the_true_peak_limiter_holds_its_ceiling_on_an_inter_sample_peak_fixture
    # a sine at a quarter of the sample rate and 45 degrees: every sample is 0.707 of the real peak
    fixture = Array.new(SAMPLE_RATE) { |i| 1.4 * Math.sin((Math::PI / 2 * i) + (Math::PI / 4)) }
    assert_operator fixture.map(&:abs).max, :<, 1.0, "the samples stay under one"
    assert_operator Mastering::TruePeak.peak(fixture), :>, 1.35, "the meter finds the peak between them"
    limiter = Mastering::Limiter.new(ceiling_db: -1.0, channels: 1)
    out = limiter.process([fixture + Array.new(2000, 0.0)]).first
    settled = out[2000, 40_000]
    ceiling = 10**(-1.0 / 20)
    assert_operator reference_true_peak(settled.first(300)), :<=, ceiling + 0.002, "-1 dBTP on a sinc reconstruction"
    assert_operator Mastering::TruePeak.peak(settled), :<=, ceiling + 0.002
    assert_operator Tape.rms(settled), :>, 0.5, "and it is not squashed beyond need"
  end

  def test_the_limiter_leaves_a_quiet_signal_alone_apart_from_its_delay_and_is_the_same_in_blocks
    quiet = [tone(300.0, 1.0, 0.2)]
    limiter = Mastering::Limiter.new(channels: 1)
    out = limiter.process(quiet).first
    d = limiter.latency
    assert_in_delta 0.0, out[d + 100, 2000].zip(quiet.first[100, 2000]).map { |a, b| (a - b).abs }.max, 1e-9
    loud = [tone(200.0, 1.0, 1.6), tone(300.0, 1.0, 1.2)]
    whole = Mastering::Limiter.new(channels: 2).process(loud)
    cut = Mastering::Limiter.new(channels: 2)
    parts = loud[0].each_slice(3001).zip(loud[1].each_slice(3001)).map { |l, r| cut.process([l, r]) }
    assert_equal whole, [parts.flat_map(&:first), parts.flat_map(&:last)]
    assert_operator whole.flatten.map(&:abs).max, :<=, 10**(-1.0 / 20) + 1e-6
  end

  def test_the_equalizer_cuts_the_low_mids_lifts_the_air_and_the_dynamic_cut_deepens_with_level
    spec = MASTER.fetch("eq")
    gain = lambda do |hz, amp|
      x = tone(hz, 1.5, amp)
      out = Mastering::Equalizer.new(spec, 1).process([x]).first
      Tape.rms(out.last(30_000)) / Tape.rms(x.last(30_000))
    end
    assert_operator gain.call(spec.dig("low_mid", "hz"), 0.01), :<, 0.95
    assert_operator gain.call(14_000.0, 0.01), :>, 1.05
    assert_in_delta 1.0, gain.call(2000.0, 0.01), 0.05
    assert_operator gain.call(spec.dig("low_mid", "hz"), 0.5), :<, gain.call(spec.dig("low_mid", "hz"), 0.01), "louder, deeper"
  end

  def test_the_three_bands_add_back_flat_and_each_is_compressed_on_its_own
    flat = MASTER.fetch("multiband").merge("bands" => MASTER.dig("multiband", "bands").map { |b| b.merge("ratio" => 1.0, "makeup_db" => 0.0) })
    [100.0, 1000.0, 6000.0].each do |hz|
      x = tone(hz, 1.5, 0.2)
      out = Mastering::Multiband.new(flat, 1).process([x]).first
      assert_in_delta 0.0, Tape.db(Tape.rms(out.last(30_000)) / Tape.rms(x.last(30_000))), 0.4, "#{hz} Hz comes through"
    end
    loud_low = tone(100.0, 2.0, 0.9)
    squeezed = Mastering::Multiband.new(MASTER.fetch("multiband"), 1).process([loud_low]).first
    assert_operator Tape.rms(squeezed.last(30_000)), :<, Tape.rms(loud_low.last(30_000)) * 0.9, "the low band is compressed"
    quiet_high = tone(6000.0, 1.0, 0.01)
    untouched = Mastering::Multiband.new(MASTER.fetch("multiband"), 1).process([quiet_high]).first
    assert_in_delta 1.0, Tape.rms(untouched.last(20_000)) / Tape.rms(quiet_high.last(20_000)), 0.15, "a quiet band is left alone"
  end

  def test_the_chain_brings_a_whole_signal_to_the_target_and_a_stream_creeps_toward_it
    music = tone(220.0, 8.0, 0.03).each_with_index.map { |v, i| v + (0.02 * Math.sin(i / 11.0)) }
    chain = Mastering::Chain.new(MASTER, channels: 2, whole: true)
    out = chain.process([music, music])
    assert_in_delta MASTER.fetch("target_lufs"), Mastering::Loudness.integrated(out), 1.5
    streamed = Mastering::Chain.new(MASTER, channels: 2)
    half = SAMPLE_RATE / 2
    gains = music.each_slice(half).map { |part| streamed.process([part, part]); streamed.gain_db }
    assert_operator gains.last, :>, gains.first, "it goes up toward the target"
    gains.each_cons(2) { |a, b| assert_operator (b - a).abs, :<=, 1.01, "by no more than two decibels a second" }
    chain.target = -20.0
    assert_in_delta(-20.0, chain.instance_variable_get(:@target), 0)
  end

  def test_the_glue_release_follows_the_tempo
    chain = Mastering::Chain.new(MASTER, channels: 1, bpm: 60.0)
    slow = chain.instance_variable_get(:@glue).instance_variable_get(:@down)
    chain.bpm = 120.0
    fast = chain.instance_variable_get(:@glue).instance_variable_get(:@down)
    assert_operator fast, :>, slow
    assert_in_delta 1.0 - Math.exp(-1.0 / (0.25 * SAMPLE_RATE)), fast, 1e-9, "half a beat at 120 is 250 ms"
  end

  def test_widening_keeps_the_mono_sum_within_half_a_decibel
    rng = Random.new(8)
    pure = tone(900.0, 1.0)
    left = Array.new(40_000) { (Math.sin(rng.rand * 7) * 0.2) + (pure[rng.rand(1000)] * 0.1) }
    right = left.each_with_index.map { |v, i| (v * 0.6) + (Math.sin(i / 3.0) * 0.1) }
    wide = Stream::Imager.new(widen: 0.9, width: 1.4).process([left, right])
    before = left.zip(right).map { |a, b| (a + b) / 2 }
    after = wide[0].zip(wide[1]).map { |a, b| (a + b) / 2 }
    assert_in_delta 0.0, Tape.db(Tape.rms(after) / Tape.rms(before)), 0.5
  end

  def test_dither_is_tpdf_of_one_lsb_and_seeded
    silence = [Array.new(20_000, 0.0)]
    dithered = Mastering::Dither.new(5).process(silence).first
    assert_equal dithered, Mastering::Dither.new(5).process(silence).first
    assert_operator dithered.map(&:abs).max, :<=, 1.0 / 32_768 * 1.0001
    assert_in_delta 0.0, dithered.sum / dithered.size * 32_768, 0.05
    assert_in_delta 1.0 / 6.0, (dithered.sum { |v| (v * 32_768)**2 } / dithered.size), 0.03, "triangular: variance a sixth of a bit squared"
  end

  def test_a_24_bit_wav_has_three_bytes_a_sample
    Dir.mktmpdir do |dir|
      path = File.join(dir, "w.wav")
      WAV.write(path, [[0.5, -0.5]], bits: 24)
      bytes = File.binread(path)
      assert_equal 24, bytes.byteslice(34, 2).unpack1("v")
      assert_equal 3, bytes.byteslice(32, 2).unpack1("v")
      assert_equal 6, bytes.bytesize - 44
      assert_equal "\x00\x00\x40".b, bytes.byteslice(44, 3)
      assert_equal "\x00\x00\xC0".b, bytes.byteslice(47, 3)
    end
  end

  def test_the_report_names_loudness_peak_crest_and_correlation
    sine = Array.new(SAMPLE_RATE * 4) { |i| 0.1 * Math.sin(2 * Math::PI * 997 * i / SAMPLE_RATE) }
    report = Mastering.report([sine, sine])
    assert_in_delta(-20.0, report[:lufs], 0.3)
    assert_in_delta(-20.0, report[:true_peak_db], 0.1)
    assert_in_delta 3.0, report[:crest_db], 0.2
    assert_in_delta 1.0, report[:correlation], 1e-6
    anti = Mastering.report([sine, sine.map(&:-@)])
    assert_in_delta(-1.0, anti[:correlation], 1e-6)
    assert_includes Mastering.report_line(report), "LUFS-I"
  end

  def test_a_render_is_mastered_to_the_target_under_the_ceiling_and_no_master_bypasses_it
    Dir.mktmpdir do |dir|
      args = ["--progression", "2", "--profile", "arp_echo", "--beats", "2", "--seed", "3", "--tape", "1"]
      out, err, status = run_dilla(*args, "--lufs", "-24", "--out", File.join(dir, "m.wav"), chdir: dir, stereo: true)
      assert status.success?, err
      assert_match(/loudness: -?\d+\.\d LUFS-I, true peak -?\d+\.\d+ dBTP/, out)
      lufs = out[/loudness: (-?\d+\.\d) LUFS-I/, 1].to_f
      peak = out[/true peak (-?\d+\.\d+) dBTP/, 1].to_f
      assert_in_delta(-24.0, lufs, 1.5)
      assert_operator peak, :<=, -0.9
      raw, err, status = run_dilla(*args, "--no-master", "--out", File.join(dir, "n.wav"), chdir: dir, stereo: true)
      assert status.success?, err
      refute_includes raw, "loudness:"
      assert_equal 16, File.binread(File.join(dir, "m.wav")).byteslice(34, 2).unpack1("v")
      _o, err, status = run_dilla(*args, "--bits", "24", "--out", File.join(dir, "b.wav"), chdir: dir, stereo: true)
      assert status.success?, err
      assert_equal 24, File.binread(File.join(dir, "b.wav")).byteslice(34, 2).unpack1("v")
    end
  end

  def test_a_show_that_cannot_keep_up_drops_the_dear_stages_and_says_so
    log = StringIO.new
    player = FakePlayer.new([])
    options = { passes: 1, seed: 5, beats: 8.0, profile: "dry", mode: "pad", voice: "pure_tone", tape: 0, decks: 1, pace: 0.0001, mono: true,
                out: File.join(Dir.mktmpdir, "x.wav") }
    show = Show.new(DATA, options, player:, out: log)
    show.run
    assert_includes log.string, "master: lightened"
    assert(show.instance_variable_get(:@master).chain.light?)
    chain = Mastering::Chain.new(MASTER, channels: 1)
    signal = [tone(300.0, 1.0, 0.3)]
    full = Mastering::Chain.new(MASTER, channels: 1).process(signal)
    chain.lighten!
    refute_equal full, chain.process(signal)
  end

  def test_mastering_is_deterministic
    options = { prog: 2, seed: 3, beats: 1.0, profile: "arp_echo" }
    a = master_whole(stereo_pass(options, 10_000_000).first)
    b = master_whole(stereo_pass(options, 10_000_000).first)
    assert_equal a, b
  end

  def master_whole(frame)
    chain = Mastering::Chain.new(MASTER, channels: 2, whole: true)
    chain.limit(chain.process(frame))
  end


  def test_streamed_wav_publishes_a_complete_file_and_refuses_replacement
    Dir.mktmpdir do |dir|
      path = File.join(dir, "take.wav")
      result = WAV.write_stream(path, frames: 4, channels: 1, block_size: 2) do |_offset, count|
        [Array.new(count, 0.25)]
      end

      assert_equal path, result
      bytes = File.binread(path)
      assert_equal "RIFF", bytes[0, 4]
      assert_equal bytes.bytesize - 8, bytes[4, 4].unpack1("V")
      assert_equal bytes.bytesize - 44, bytes[40, 4].unpack1("V")
      original = bytes.dup

      assert_raises(Errno::EEXIST) do
        WAV.write_stream(path, frames: 1, channels: 1) { |_offset, count| [Array.new(count, 0.0)] }
      end
      assert_equal original, File.binread(path)
    end
  end

  def test_failed_streamed_wav_never_publishes_a_partial_destination
    Dir.mktmpdir do |dir|
      path = File.join(dir, "broken.wav")
      error = assert_raises(RuntimeError) do
        WAV.write_stream(path, frames: 4, channels: 1, block_size: 2) do
          raise "synthesis failed"
        end
      end

      assert_match(/synthesis failed/, error.message)
      refute File.exist?(path)
      assert_empty Dir.glob(File.join(dir, "studio-output-*"))
    end
  end

  def test_video_export_terminates_a_timed_out_encoder_and_keeps_source_audio
    Dir.mktmpdir do |dir|
      audio = File.join(dir, "source.wav")
      video = File.join(dir, "timed-out.mp4")
      File.binwrite(audio, "existing source audio")
      previous_timeout = ENV["DILLA_FFMPEG_TIMEOUT"]
      ENV["DILLA_FFMPEG_TIMEOUT"] = "1"

      with_fake_ffmpeg(dir, "sleep 10") do
        error = assert_raises(Dilla::Video::Error) do
          Dilla::Video.render(audio:, output: video, preset: "dilla_heavy")
        end
        assert_match(/timed out/, error.message)
      end

      refute File.exist?(video)
      assert_equal "existing source audio", File.binread(audio)
    ensure
      previous_timeout.nil? ? ENV.delete("DILLA_FFMPEG_TIMEOUT") : ENV["DILLA_FFMPEG_TIMEOUT"] = previous_timeout
    end
  end
end
