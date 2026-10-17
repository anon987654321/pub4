# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "rbconfig"
require "tmpdir"
require_relative "../dilla/lib/dilla"

class DillaReferenceTest < Minitest::Test
  DIR = File.expand_path("../dilla", __dir__)
  SCRIPT = File.join(DIR, "dilla.rb")

  def test_parses_the_linked_youtube_audio_source_and_ignores_tracking_parameters
    parsed = Dilla::Reference.parse_url("https://youtu.be/mx9NU4LmDwM?si=tracking")
    assert_equal "mx9NU4LmDwM", parsed.fetch(:id)
    assert_equal "https://www.youtube.com/watch?v=mx9NU4LmDwM", parsed.fetch(:url)
  end

  def test_rejects_playlists_and_non_youtube_hosts
    assert_raises(Dilla::Reference::Error) do
      Dilla::Reference.parse_url("https://www.youtube.com/playlist?list=PL123")
    end
    assert_raises(Dilla::Reference::Error) do
      Dilla::Reference.parse_url("https://example.com/watch?v=mx9NU4LmDwM")
    end
  end

  def test_cli_defines_reference_modules_before_dispatching_subcommands
    [["reference", "--help"], ["industrial-techno", "--help"]].each do |args|
      out, err, status = Open3.capture3(RbConfig.ruby, SCRIPT, *args, chdir: DIR)
      assert status.success?, "#{args.first} --help failed: #{out}\n#{err}"
      assert_match(/Usage: ruby dilla\.rb/, out)
    end
  end

  def test_profile_parameters_are_bounded_and_use_audio_measurements
    mix = {
      "tempo" => { "bpm" => 142.0, "confidence" => 0.8 },
      "spectral_bands_db" => {
        "sub_25_120_hz" => -10.0, "low_mid_120_500_hz" => -26.0,
        "mid_500_4000_hz" => -20.0, "high_4000_plus_hz" => -6.0
      }
    }
    profile = Dilla::Reference.profile_for(mix, style: "industrial techno")
    assert_equal "industrial_techno", profile.fetch("genre")
    assert_equal "industrial_techno", profile.fetch("style_key")
    assert_equal 142, profile.fetch("target_bpm")
    params = profile.fetch("parameters")
    assert_operator params.fetch("rumble_level"), :between?, 0.05, 0.35
    assert_operator params.fetch("hat_probability"), :between?, 0.1, 0.98
    assert_operator params.fetch("distortion_drive"), :between?, 1.0, 4.0
  end

  def test_missing_spectral_measurements_fall_back_without_crashing
    mix = {
      "tempo" => { "bpm" => nil },
      "spectral_bands_db" => {
        "sub_25_120_hz" => nil, "low_mid_120_500_hz" => nil,
        "mid_500_4000_hz" => nil, "high_4000_plus_hz" => nil
      }
    }
    profile = Dilla::Reference.profile_for(mix, style: "industrial_techno")
    assert_equal 138, profile.fetch("target_bpm")
    assert_operator profile.fetch("parameters").fetch("rumble_level"), :>=, 0.05
    assert_operator profile.fetch("parameters").fetch("distortion_drive"), :>=, 1.0
  end

  def test_j_dilla_reference_creates_a_hip_hop_profile_not_a_techno_profile
    mix = { "tempo" => { "bpm" => 92.0, "confidence" => 0.8 }, "spectral_bands_db" => {} }
    profile = Dilla::Reference.profile_for(mix, style: "J Dilla")
    assert_equal "hip_hop", profile.fetch("genre")
    assert_equal "j_dilla", profile.fetch("style_key")
    assert_equal 92, profile.fetch("target_bpm")
    assert_equal "dilla_shadow", profile.fetch("groove_profile")
    refute profile.fetch("parameters", {}).key?("rumble_level")
  end

  def test_unlabelled_reference_stays_general_instead_of_becoming_techno
    mix = { "tempo" => { "bpm" => 124.0 }, "spectral_bands_db" => {} }
    profile = Dilla::Reference.profile_for(mix)
    assert_equal "general", profile.fetch("genre")
    assert_equal "general", profile.fetch("style_key")
    assert_equal 124, profile.fetch("target_bpm")
  end

  def test_rhythm_density_steers_techno_hat_and_metal_density
    mix = {
      "tempo" => { "bpm" => 140.0 },
      "spectral_bands_db" => {
        "sub_25_120_hz" => -14.0, "low_mid_120_500_hz" => -24.0,
        "mid_500_4000_hz" => -20.0, "high_4000_plus_hz" => -10.0
      }
    }
    dense = Dilla::Reference.profile_for(mix, style: "industrial_techno")
    sparse = Dilla::Reference.profile_for(mix, style: "industrial_techno")
    dense_base = dense.fetch("parameters").dup
    sparse_base = sparse.fetch("parameters").dup

    Dilla::Reference.apply_rhythm_balance(dense, "onset_density_per_bar" => 24.0)
    Dilla::Reference.apply_rhythm_balance(sparse, "onset_density_per_bar" => 8.0)

    assert_in_delta dense_base.fetch("hat_probability") + 0.04, dense.fetch("parameters").fetch("hat_probability"), 0.001
    assert_in_delta dense_base.fetch("metal_probability") + 0.03, dense.fetch("parameters").fetch("metal_probability"), 0.001
    assert_in_delta sparse_base.fetch("hat_probability") - 0.04, sparse.fetch("parameters").fetch("hat_probability"), 0.001
    assert_in_delta sparse_base.fetch("metal_probability") - 0.03, sparse.fetch("parameters").fetch("metal_probability"), 0.001
  end

  def test_stem_balance_steers_techno_rumble_and_duck_with_bounded_adjustments
    mix = {
      "tempo" => { "bpm" => 140.0 },
      "spectral_bands_db" => {
        "sub_25_120_hz" => -14.0, "low_mid_120_500_hz" => -24.0,
        "mid_500_4000_hz" => -20.0, "high_4000_plus_hz" => -10.0
      }
    }
    profile = Dilla::Reference.profile_for(mix, style: "industrial_techno")
    base_rumble = profile.fetch("parameters").fetch("rumble_level")
    base_duck = profile.fetch("parameters").fetch("rumble_duck_depth")

    Dilla::Reference.apply_stem_balance(profile, {
      "bass_energy_share" => 0.5, "drums_energy_share" => 0.5
    })

    assert_in_delta base_rumble + 0.03, profile.fetch("parameters").fetch("rumble_level"), 0.001
    assert_in_delta base_duck + 0.055, profile.fetch("parameters").fetch("rumble_duck_depth"), 0.001
    assert_operator profile.fetch("parameters").fetch("rumble_level"), :between?, 0.05, 0.35
    assert_operator profile.fetch("parameters").fetch("rumble_duck_depth"), :between?, 0.3, 0.95
  end

  def test_rhythm_summary_measures_onset_density_and_grid_looseness
    sample_rate = 100
    bpm = 100.0
    subdivision = sample_rate * 60.0 / bpm / 4.0
    samples = Array.new(sample_rate * 30, 0.0)
    (0...(samples.size / subdivision).floor).each do |step|
      position = (step * subdivision).round + (step.odd? ? 2 : 0)
      samples[position] = 1.0 if position < samples.size
      samples[position + 1] = 0.5 if position + 1 < samples.size
    end

    features = Dilla::Reference.summarize_rhythm_envelope(samples, bpm:, sample_rate:)
    assert_operator features.fetch("onset_density_per_bar"), :>, 14.0
    assert_operator features.fetch("timing_spread_ms"), :>=, 5.0
    assert_operator features.fetch("timing_spread_ms"), :<=, 20.0
    assert_operator features.fetch("offbeat_onset_share"), :>, 0.5
    assert_operator features.fetch("offbeat_onset_share"), :<=, 1.0
  end

  def test_rhythm_summary_declines_when_the_envelope_has_too_little_evidence
    assert_empty Dilla::Reference.summarize_rhythm_envelope(Array.new(100, 0.0), bpm: 100.0, sample_rate: 100)
    assert_empty Dilla::Reference.summarize_rhythm_envelope(Array.new(1_000, 0.0), bpm: 100.0, sample_rate: 100)
  end

  def test_demucs_stem_energy_shares_capture_relative_part_balance
    tracks = {
      "mix" => { "rms_db" => -6.0 },
      "drums" => { "rms_db" => -10.0 },
      "bass" => { "rms_db" => -13.0 },
      "other" => { "rms_db" => -13.0 },
      "vocals" => { "rms_db" => nil }
    }

    features = Dilla::Reference.stem_energy_features(tracks)
    assert_in_delta 1.0, features.values.sum, 0.002
    assert_in_delta 0.5, features.fetch("drums_energy_share"), 0.002
    assert_in_delta 0.25, features.fetch("bass_energy_share"), 0.002
    assert_in_delta 0.25, features.fetch("other_energy_share"), 0.002
    refute features.key?("vocals_energy_share")
  end

  def test_stem_energy_features_omit_unavailable_or_silent_roles
    assert_empty Dilla::Reference.stem_energy_features("mix" => { "rms_db" => -6.0 })
    assert_empty Dilla::Reference.stem_energy_features(
      "drums" => { "rms_db" => nil }, "bass" => { "rms_db" => "-inf" }
    )
  end

  def test_learned_profile_averages_multiple_references_of_the_same_style
    first = {
      "style_key" => "industrial_techno", "genre" => "industrial_techno",
      "target_bpm" => 120, "measured_bpm" => 121.0, "source_duration_seconds" => 24.0,
      "reference_fingerprint" => "1111111111111111",
      "features" => { "brightness" => 0.2, "low_frequency_weight" => 0.4 },
      "parameters" => { "rumble_level" => 0.1, "distortion_drive" => 1.5 }
    }
    second = {
      "style_key" => "industrial_techno", "genre" => "industrial_techno",
      "target_bpm" => 140, "measured_bpm" => 139.0, "source_duration_seconds" => 30.0,
      "reference_fingerprint" => "2222222222222222",
      "features" => { "brightness" => 0.8, "low_frequency_weight" => 0.6 },
      "parameters" => { "rumble_level" => 0.2, "distortion_drive" => 2.5 }
    }

    learned = Dilla::Reference.aggregate_profiles("industrial_techno", [first, second])
    assert_equal 2, learned.fetch("reference_count")
    assert_equal 130, learned.fetch("target_bpm")
    assert_equal 130.0, learned.fetch("measured_bpm")
    assert_equal 30.0, learned.fetch("source_duration_seconds")
    assert_in_delta 0.5, learned.fetch("features").fetch("brightness"), 0.0001
    assert_in_delta 0.15, learned.fetch("parameters").fetch("rumble_level"), 0.0001
    assert_equal %w[1111111111111111 2222222222222222], learned.fetch("reference_fingerprints")
  end

  def test_general_reference_does_not_erase_the_active_style
    Dir.mktmpdir do |dir|
      assert_equal "j_dilla", Dilla::Reference.write_active_style("J Dilla", root: dir)
      assert_equal "general", Dilla::Reference.write_active_style("general", root: dir)
      assert_equal "j_dilla", Dilla::Reference.active_style(root: dir)
    end
  end

  def test_profiles_are_scoped_to_a_style
    dilla = Dilla::Reference.profile_path("j_dilla")
    techno = Dilla::Reference.profile_path("industrial_techno")
    assert_includes dilla, File.join("profiles", "j_dilla")
    assert_includes techno, File.join("profiles", "industrial_techno")
    refute_equal dilla, techno
  end

  def test_industrial_renderer_does_not_mistake_hip_hop_profiles_for_techno
    Dir.mktmpdir do |dir|
      path = File.join(dir, "profile.json")
      File.write(path, JSON.generate("genre" => "hip_hop", "style_key" => "j_dilla"))
      refute Dilla::IndustrialTechno.profile_matches_industrial_techno?(path)
      File.write(path, JSON.generate("genre" => "industrial_techno", "style_key" => "industrial_techno"))
      assert Dilla::IndustrialTechno.profile_matches_industrial_techno?(path)
    end
  end

  def test_automatic_generation_plan_uses_reference_duration_and_internal_seed
    profile = { "source_duration_seconds" => 24.0, "reference_fingerprint" => "fixture" }
    plan = Dilla::IndustrialTechno.generation_plan(profile:, bpm: 120)
    assert_equal 12, plan.fetch(:bars)
    assert_operator plan.fetch(:seed), :>=, 0
    assert_operator plan.fetch(:seed), :<=, 0xffff_ffff
  end

  def test_automatic_generation_plan_uses_safe_defaults_without_reference_duration
    plan = Dilla::IndustrialTechno.generation_plan(profile: nil, bpm: 138)
    assert_equal 16, plan.fetch(:bars)
    assert_operator plan.fetch(:seed), :>=, 0
    assert_operator plan.fetch(:seed), :<=, 0xffff_ffff
  end

  def test_reference_mix_balance_moves_relative_to_dillas_own_defaults
    original = { "kick" => 6.0, "snare" => 10.0, "clap" => 8.0, "hat" => 0.0, "perc" => -4.0, "chords" => -3.0 }

    adjusted = apply_reference_mix_balance(original, drum_balance: 1.5, chord_balance: -0.5)

    assert_equal 7.5, adjusted.fetch("kick")
    assert_equal 11.5, adjusted.fetch("snare")
    assert_equal 9.5, adjusted.fetch("clap")
    assert_equal 1.5, adjusted.fetch("hat")
    assert_equal -2.5, adjusted.fetch("perc")
    assert_equal -3.5, adjusted.fetch("chords")
    assert_equal({ "kick" => 6.0, "snare" => 10.0, "clap" => 8.0, "hat" => 0.0, "perc" => -4.0, "chords" => -3.0 }, original)
  end

  def test_reference_mix_balance_clamps_untrusted_offsets
    levels = { "kick" => 6.0, "chords" => -3.0 }
    adjusted = apply_reference_mix_balance(levels, drum_balance: 50.0, chord_balance: -50.0)
    assert_equal 8.0, adjusted.fetch("kick")
    assert_equal -5.0, adjusted.fetch("chords")
  end

  def test_streamed_wav_header_and_lengths_are_valid
    Dir.mktmpdir do |dir|
      path = File.join(dir, "small.wav")
      WAV.write_stream(path, frames: 16, channels: 2, bits: 24, block_size: 5) do |_offset, count|
        [Array.new(count, 0.1), Array.new(count, -0.1)]
      end
      bytes = File.binread(path)
      assert_equal "RIFF", bytes[0, 4]
      assert_equal "WAVE", bytes[8, 4]
      assert_equal 44 + 16 * 2 * 3, bytes.bytesize
      assert_equal bytes.bytesize - 8, bytes[4, 4].unpack1("V")
      assert_equal bytes.bytesize - 44, bytes[40, 4].unpack1("V")
    end
  end

  def test_streamed_wav_refuses_overwrite_and_cleans_partial_files
    Dir.mktmpdir do |dir|
      existing = File.join(dir, "keep.wav")
      File.write(existing, "operator-owned")
      assert_raises(Errno::EEXIST) do
        WAV.write_stream(existing, frames: 1, channels: 1) { |_offset, count| [Array.new(count, 0.0)] }
      end
      assert_equal "operator-owned", File.read(existing)

      partial = File.join(dir, "partial.wav")
      assert_raises(ArgumentError) do
        WAV.write_stream(partial, frames: 2, channels: 1) { |_offset, _count| [[]] }
      end
      refute File.exist?(partial)
    end
  end

  def test_industrial_render_writes_a_new_stereo_wav_and_refuses_overwrite
    Dir.mktmpdir do |dir|
      path = File.join(dir, "industrial.wav")
      Dilla::IndustrialTechno.render(path, bpm: 100, bars: 1, seed: 7)
      bytes = File.binread(path)
      assert_equal "RIFF", bytes[0, 4]
      assert_equal "WAVE", bytes[8, 4]
      assert_equal 2, bytes[22, 2].unpack1("v")
      assert_raises(Errno::EEXIST) do
        Dilla::IndustrialTechno.render(path, bpm: 100, bars: 1, seed: 7)
      end
    end
  end
  def test_temporal_energy_summary_reports_coarse_dynamics_without_audio_tools
    samples = Array.new(60, 0.01) + Array.new(60, 0.001) +
              Array.new(60, 0.005) + Array.new(60, 0.01)
    result = Dilla::Reference.summarize_energy_envelope(samples, sample_rate: 4, window_seconds: 15)

    assert_equal 4, result.fetch("window_count")
    assert_equal [0, 15, 30, 45], result.fetch("windows").map { |window| window.fetch("start_seconds") }
    assert_in_delta 10.0, result.fetch("summary").fetch("rms_range_p95_p05_db"), 0.01
    assert_operator result.fetch("summary").fetch("rms_stddev_db"), :>, 0.0
  end

  def test_temporal_energy_summary_omits_dynamic_statistics_without_three_windows
    result = Dilla::Reference.summarize_energy_envelope(Array.new(120, 0.01), sample_rate: 4, window_seconds: 15)

    assert_equal 2, result.fetch("window_count")
    assert_empty result.fetch("summary")
  end

  def test_essentia_summary_extracts_independent_features_without_chord_progressions
    document = {
      "rhythm" => { "bpm" => 91.8, "bpm_histogram_first_peak_bpm" => 92.0,
                    "bpm_histogram_second_peak_bpm" => 184.0, "beats_count" => 120,
                    "onset_rate" => 2.6 },
      "tonal" => { "key_key" => "A", "key_scale" => "minor",
                   "chords_progression" => "must not be copied" },
      "lowlevel" => { "spectral_centroid" => { "mean" => 1850.25 },
                      "spectral_entropy" => { "mean" => 0.72 } }
    }
    summary = Dilla::Reference.essentia_descriptor_summary(document)

    assert_equal 91.8, summary.fetch("bpm")
    assert_equal "A", summary.fetch("key")
    assert_equal "minor", summary.fetch("scale")
    assert_equal 1850.25, summary.fetch("spectral_centroid_mean_hz")
    refute summary.key?("chords_progression")
  end

  def test_tempo_crosscheck_exposes_half_double_time_ambiguity
    result = Dilla::Reference.tempo_crosscheck(
      { "bpm" => 92.0 }, { "bpm" => 184.0 }
    )

    assert_equal "half_double_ambiguity", result.fetch("status")
    assert_equal 92.0, result.fetch("ffmpeg_bpm")
    assert_equal 184.0, result.fetch("essentia_bpm")
  end

  def test_rhythm_source_is_explicit_about_demucs_vs_full_mix_proxy
    audio = "/references/source.wav"
    stem, source = Dilla::Reference.rhythm_source_for(
      ["/references/stems/other.wav", "/references/stems/drums.wav"], audio
    )
    assert_equal "/references/stems/drums.wav", stem
    assert_equal "demucs_drums_stem", source

    stem, source = Dilla::Reference.rhythm_source_for([], audio)
    assert_equal audio, stem
    assert_equal "full_mix_proxy", source
  end

  def test_analysis_timeouts_scale_for_album_length_and_remain_bounded
    assert_equal 450, Dilla::Reference.analysis_timeout(900)
    assert_equal 3_600, Dilla::Reference.analysis_timeout(7_200)
    assert_equal 120, Dilla::Reference.analysis_timeout(1)
  end

end
