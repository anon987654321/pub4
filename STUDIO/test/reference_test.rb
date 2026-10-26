# frozen_string_literal: true

require_relative "minitest_helper"
require "open3"
require "rbconfig"
require "tmpdir"
require_relative "../dilla/dilla"

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

  def test_accepts_both_operator_supplied_dilla_references_without_playlist_tracking
    sources = {
      "https://www.youtube.com/watch?v=22OnSvf-SDc&list=RD22OnSvf-SDc&start_radio=1" => "22OnSvf-SDc",
      "https://www.youtube.com/watch?v=XKB5h2tJQHQ&list=RDXKB5h2tJQHQ&start_radio=1&pp=oAcB" => "XKB5h2tJQHQ"
    }

    sources.each do |url, expected_id|
      parsed = Dilla::Reference.parse_url(url)
      assert_equal expected_id, parsed.fetch(:id)
      assert_equal "https://www.youtube.com/watch?v=#{expected_id}", parsed.fetch(:url)
    end
  end

  def test_reference_urls_reject_playlist_only_inputs_even_when_they_are_mix_playlists
    [
      "https://www.youtube.com/playlist?list=RD22OnSvf-SDc",
      "https://www.youtube.com/playlist?list=RDXKB5h2tJQHQ"
    ].each do |url|
      assert_raises(Dilla::Reference::Error) { Dilla::Reference.parse_url(url) }
    end
  end

  def test_cli_defines_reference_modules_before_dispatching_subcommands
    [["reference", "--help"], ["industrial-techno", "--help"]].each do |args|
      out, err, status = Open3.capture3(RbConfig.ruby, SCRIPT, *args, chdir: DIR)
      assert status.success?, "#{args.first} --help failed: #{out}\n#{err}"
      assert_match(/Usage: ruby dilla\.rb/, out)
      assert_includes out, "--no-libsonare" if args.first == "reference"
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
    assert_includes 0.05..0.35, params.fetch("rumble_level")
    assert_includes 0.1..0.98, params.fetch("hat_probability")
    assert_includes 1.0..4.0, params.fetch("distortion_drive")
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
    assert_includes 0.05..0.35, profile.fetch("parameters").fetch("rumble_level")
    assert_includes 0.3..0.95, profile.fetch("parameters").fetch("rumble_duck_depth")
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
    assert_equal "mix_level_onset_proxy_not_drum_transcription", features.fetch("grid_measurement")
    assert_equal 16, features.fetch("sixteenth_grid_hits_per_bar").length
    assert_equal 16, features.fetch("sixteenth_grid_strength_share").length
    assert features.fetch("sixteenth_grid_hits_per_bar").all?(&:positive?)
    assert_in_delta 1.0, features.fetch("sixteenth_grid_strength_share").sum, 0.002
    assert_equal 150.0, features.fetch("sixteenth_cell_ms")
  end

  def test_rhythm_zoom_summaries_report_complete_four_eight_and_sixteen_bar_windows
    sample_rate = 100
    bpm = 120.0
    subdivision = sample_rate * 60.0 / bpm / 4.0
    samples = Array.new(sample_rate * 32, 0.0)
    (0...(samples.size / subdivision).floor).each do |step|
      position = (step * subdivision).round
      samples[position] = 1.0 if position < samples.size
      samples[position + 1] = 0.5 if position + 1 < samples.size
    end

    windows = Dilla::Reference.rhythm_zoom_summaries(samples, bpm:, sample_rate:)

    assert_equal [
      [4, 0.0, 8.0], [8, 0.0, 16.0], [16, 0.0, 32.0],
      [4, 8.0, 16.0], [4, 16.0, 24.0], [8, 16.0, 32.0], [4, 24.0, 32.0]
    ], windows.map { |window| [window.fetch("bars"), window.fetch("start_seconds"), window.fetch("end_seconds")] }
    windows.each do |window|
      features = window.fetch("features")
      assert_equal 16, features.fetch("sixteenth_grid_strength_share").length
      assert_equal "mix_level_onset_proxy_not_drum_transcription", features.fetch("grid_measurement")
    end
    assert_empty Dilla::Reference.rhythm_zoom_summaries(samples.first(799), bpm:, sample_rate:)
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

  def test_libsonare_summary_reports_groove_and_structure_without_chord_names
    document = {
      "bpm" => 143.6, "bpm_confidence" => 0.84,
      "key" => { "name" => "A minor", "confidence" => 0.77 },
      "time_signature" => { "numerator" => 4, "denominator" => 4 },
      "beats" => [{ "time" => 0.0 }, { "time" => 0.418 }, { "time" => 0.836 }, { "time" => 1.28 }],
      "downbeat_indices" => [0],
      "chords" => [{ "name" => "Am", "start" => 0.0 }, { "name" => "F", "start" => 1.2 }],
      "sections" => [{ "type" => "intro" }, { "type" => "drop" }, { "type" => "drop" }],
      "timbre" => { "brightness" => 0.71, "warmth" => 0.24 },
      "dynamics" => { "dynamic_range_db" => 10.5, "is_compressed" => false },
      "rhythm" => { "syncopation" => 0.67, "groove_type" => "driving" },
      "form" => "intro-drop"
    }

    summary = Dilla::Reference.libsonare_descriptor_summary(document)

    assert_equal 143.6, summary.fetch("bpm")
    assert_equal 0.84, summary.fetch("bpm_confidence")
    assert_equal "A minor", summary.fetch("key")
    assert_equal "4/4", summary.fetch("time_signature")
    assert_equal 4, summary.fetch("beats_count")
    assert_in_delta 418.0, summary.fetch("beat_interval_median_ms"), 5.0
    assert_operator summary.fetch("beat_interval_cv_pct"), :>, 0.0
    assert_equal 1, summary.fetch("downbeats_count")
    assert_equal 2, summary.fetch("chord_count")
    assert_equal 3, summary.fetch("section_count")
    assert_equal %w[drop intro], summary.fetch("section_types")
    assert_equal 0.71, summary.fetch("timbre_brightness")
    assert_equal 10.5, summary.fetch("dynamics_dynamic_range_db")
    assert_equal 0.67, summary.fetch("rhythm_syncopation")
    assert_equal "driving", summary.fetch("rhythm_groove_type")
    assert_equal "intro-drop", summary.fetch("form")
    refute summary.key?("chords"), "exact chord names must not enter the compact production summary"
    refute summary.key?("chord_names")
  end

  def test_libsonare_summary_ignores_malformed_and_non_finite_values
    assert_empty Dilla::Reference.libsonare_descriptor_summary(nil)
    summary = Dilla::Reference.libsonare_descriptor_summary(
      "bpm" => Float::INFINITY,
      "bpm_confidence" => 1.4,
      "key" => { "name" => " ", "confidence" => -0.1 },
      "time_signature" => { "numerator" => 4.5, "denominator" => 4 },
      "beats" => "not-a-list",
      "sections" => [{ "type" => 17 }, nil]
    )
    refute summary.key?("bpm")
    refute summary.key?("bpm_confidence")
    refute summary.key?("key")
    refute summary.key?("time_signature")
    refute summary.key?("beats_count")
    assert_equal 1, summary.fetch("section_count")
    refute summary.key?("section_types")
  end

  def test_libsonare_is_optional_when_its_executable_is_missing
    Dir.mktmpdir do |dir|
      result = Dilla::Reference.stub(:executable, nil) do
        Dilla::Reference.libsonare("/audio/track.wav", dir, source_duration: 60)
      end
      assert_equal "unavailable", result.fetch("status")
      refute result.key?("summary")
    end
  end

  def test_libsonare_skips_sources_over_the_memory_bound_before_tool_discovery
    Dir.mktmpdir do |dir|
      resolver = ->(*) { flunk("must not discover a tool for a source over the cap") }
      result = Dilla::Reference.stub(:executable, resolver) do
        Dilla::Reference.libsonare("/audio/album.wav", dir, max_duration: 7_200, source_duration: 901)
      end
      assert_equal "skipped_duration", result.fetch("status")
      assert_equal 900, result.fetch("max_duration_seconds")
    end
  end

  def test_libsonare_skips_sources_with_unknown_duration
    Dir.mktmpdir do |dir|
      resolver = ->(*) { flunk("must not launch an analyzer for unknown-duration input") }
      result = Dilla::Reference.stub(:executable, resolver) do
        Dilla::Reference.libsonare("/audio/unknown.wav", dir, source_duration: nil)
      end
      assert_equal "skipped_unknown_duration", result.fetch("status")
    end
  end

  def test_libsonare_converts_unsupported_formats_and_parses_json
    Dir.mktmpdir do |dir|
      audio = File.join(dir, "track.flac")
      File.write(audio, "fixture audio bytes")
      calls = []
      document = {
        "bpm" => 143.6, "key" => { "name" => "A minor", "confidence" => 0.8 },
        "beats" => [], "chords" => [], "sections" => []
      }
      resolver = lambda do |env_name, _default_name|
        env_name == "LIBSONARE_BIN" ? "/opt/sonare" : "/opt/ffmpeg"
      end
      capture = lambda do |label, *command, timeout:|
        calls << { label:, command:, timeout: }
        if label == "libsonare input conversion"
          File.write(command.last, "converted wav bytes")
          ["", ""]
        else
          [JSON.generate(document), ""]
        end
      end

      result = Dilla::Reference.stub(:executable, resolver) do
        Dilla::Reference.stub(:capture!, capture) do
          Dilla::Reference.libsonare(audio, dir, max_duration: 900, source_duration: 60)
        end
      end

      assert_equal "analyzed", result.fetch("status")
      assert_equal 143.6, result.fetch("summary").fetch("bpm")
      assert File.file?(File.join(dir, "libsonare_features.json"))
      assert_equal 2, calls.size
      assert_equal "ffmpeg", File.basename(calls[0].fetch(:command).first)
      assert_equal "sonare", File.basename(calls[1].fetch(:command).first)
      assert_equal ["analyze", "--json"], [calls[1].fetch(:command)[1], calls[1].fetch(:command)[3]]
      assert_match(/\.wav\z/, calls[1].fetch(:command)[2])
      assert calls.all? { |call| call.fetch(:timeout).positive? }
      refute Dir.children(dir).any? { |name| name.start_with?("libsonare-input-") },
             "temporary conversion must be removed"
    end
  end

  def test_libsonare_wav_input_uses_an_argument_vector_without_shell_interpolation
    Dir.mktmpdir do |dir|
      audio = File.join(dir, "track ' $(not-a-command).wav")
      File.write(audio, "fixture audio bytes")
      commands = []
      resolver = ->(env_name, _default_name) { env_name == "LIBSONARE_BIN" ? "/opt/sonare" : nil }
      capture = lambda do |_label, *command, timeout:|
        commands << [command, timeout]
        [JSON.generate("bpm" => 91.0, "beats" => [], "chords" => [], "sections" => []), ""]
      end
      result = Dilla::Reference.stub(:executable, resolver) do
        Dilla::Reference.stub(:capture!, capture) do
          Dilla::Reference.libsonare(audio, dir, source_duration: 30)
        end
      end

      assert_equal "analyzed", result.fetch("status")
      assert_equal 1, commands.size
      assert_equal ["analyze", audio, "--json"], commands.first.first[1..3]
    end
  end

  def test_libsonare_reports_missing_ffmpeg_for_conversion
    Dir.mktmpdir do |dir|
      resolver = ->(env_name, _default_name) { env_name == "LIBSONARE_BIN" ? "/opt/sonare" : nil }
      result = Dilla::Reference.stub(:executable, resolver) do
        Dilla::Reference.libsonare("/audio/track.flac", dir, source_duration: 60)
      end
      assert_equal "unavailable", result.fetch("status")
      assert_includes result.fetch("message"), "ffmpeg unavailable"
    end
  end

  def test_libsonare_malformed_output_and_timeouts_are_explicit_failures
    Dir.mktmpdir do |dir|
      audio = File.join(dir, "track.wav")
      File.write(audio, "fixture audio bytes")
      resolver = ->(_env_name, _default_name) { "/opt/sonare" }
      invalid = Dilla::Reference.stub(:executable, resolver) do
        Dilla::Reference.stub(:capture!, ->(_label, *args, **kwargs) { ["not json", ""] }) do
          Dilla::Reference.libsonare(audio, dir, source_duration: 60)
        end
      end
      assert_equal "failed", invalid.fetch("status")
      assert_match(/invalid libsonare output/, invalid.fetch("message"))

      timeout = Dilla::Reference.stub(:executable, resolver) do
        Dilla::Reference.stub(:capture!, ->(label, *args, **kwargs) { raise Dilla::Reference::Error, "#{label} timed out after #{kwargs[:timeout]}s" }) do
          Dilla::Reference.libsonare(audio, dir, source_duration: 60)
        end
      end
      assert_equal "failed", timeout.fetch("status")
      assert_match(/timed out/, timeout.fetch("message"))
    end
  end

  def test_libsonare_tempo_crosscheck_names_the_engine_and_detects_half_double_time
    agreement = Dilla::Reference.tempo_crosscheck({ "bpm" => 143.0 }, { "bpm" => 144.5 }, engine: "libsonare")
    assert_equal "agreement", agreement.fetch("status")
    assert_equal 144.5, agreement.fetch("libsonare_bpm")

    ambiguous = Dilla::Reference.tempo_crosscheck({ "bpm" => 72.0 }, { "bpm" => 144.0 }, engine: "libsonare")
    assert_equal "half_double_ambiguity", ambiguous.fetch("status")
    assert_equal 144.0, ambiguous.fetch("libsonare_bpm")

    insufficient = Dilla::Reference.tempo_crosscheck({ "bpm" => nil }, {}, engine: "libsonare")
    assert_equal "insufficient_evidence", insufficient.fetch("status")
  end

  def test_reference_report_includes_optional_libsonare_state_and_crosscheck
    Dir.mktmpdir do |dir|
      path = File.join(dir, "report.md")
      Dilla::Reference.write_report(
        path, { "mix" => { "tempo" => { "bpm" => 143.0 }, "spectral_bands_db" => {} } },
        { "status" => "not_run" }, { "style_key" => "industrial_techno" },
        { "reference_count" => 1 }, essentia: { "status" => "unavailable" },
        libsonare: { "status" => "analyzed", "summary" => { "bpm" => 143.2, "rhythm_groove_type" => "driving" } },
        tempo_crosscheck: { "status" => "agreement" },
        libsonare_tempo_crosscheck: { "status" => "half_double_ambiguity" },
        rhythm_analysis: {
          "source" => "full_mix_proxy",
          "features" => { "timing_spread_ms" => 12.0, "grid_measurement" => "mix_level_onset_proxy_not_drum_transcription" },
          "zoom_windows" => [{
            "bars" => 8, "start_seconds" => 0.0, "end_seconds" => 16.0,
            "features" => { "timing_spread_ms" => 12.0, "onset_density_per_bar" => 16.0,
                            "offbeat_onset_share" => 0.6, "sixteenth_grid_strength_share" => Array.new(16, 0.0625) }
          }]
        },
        source: { "source_type" => "local_audio" }
      )

      report = File.read(path)
      assert_includes report, "Libsonare status: analyzed"
      assert_includes report, "libsonare.bpm: 143.2"
      assert_includes report, "libsonare.rhythm_groove_type: driving"
      assert_includes report, "Tempo cross-check: FFmpeg versus libsonare"
      assert_includes report, "half_double_ambiguity"
      assert_includes report, "Four-, eight- and sixteen-bar rhythm windows"
      assert_includes report, "mix/stem-envelope proxies"
      assert_includes report, "| 8 | 0.0 | 16.0 | 12.0 | 16.0 | 0.6 |"
    end
  end

  def test_reference_report_includes_frequency_bands_for_the_mix_and_drums_stem
    Dir.mktmpdir do |dir|
      path = File.join(dir, "report.md")
      Dilla::Reference.write_report(
        path,
        {
          "mix" => {
            "tempo" => { "bpm" => 92.0 },
            "spectral_bands_db" => {
              "sub_25_120_hz" => -12.0, "high_4000_plus_hz" => -9.0
            }
          },
          "drums" => {
            "rms_db" => -8.0,
            "spectral_bands_db" => {
              "sub_25_120_hz" => -15.0, "high_4000_plus_hz" => -7.0
            }
          }
        },
        { "status" => "separated" }, { "style_key" => "j_dilla" },
        { "reference_count" => 1 }, source: { "source_type" => "local_audio" }
      )

      report = File.read(path)
      assert_includes report, "### mix"
      assert_includes report, "### drums"
      assert_includes report, "- sub_25_120_hz: -12.0 dB"
      assert_includes report, "- high_4000_plus_hz: -7.0 dB"
      assert_equal 2, report.scan(/^### (?:mix|drums)$/).length
    end
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

  def test_capture_delegates_to_the_shared_bounded_subprocess_with_argv_intact
    calls = []
    status = Object.new
    status.define_singleton_method(:success?) { true }
    capture = lambda do |*command, timeout:, **options|
      calls << { command:, timeout:, options: }
      ["stdout", "stderr", status]
    end

    result = Studio::Subprocess.stub(:capture3, capture) do
      Dilla::Reference.capture!("band analysis", "path with spaces", "arg;safe", timeout: 5)
    end

    assert_equal ["stdout", "stderr"], result
    assert_equal ["path with spaces", "arg;safe"], calls.fetch(0).fetch(:command)
    assert_equal 5, calls.fetch(0).fetch(:timeout)
    assert_empty calls.fetch(0).fetch(:options)
  end

  def test_capture_translates_shared_subprocess_timeouts_to_reference_errors
    capture = lambda do |*_command, timeout:, **_options|
      raise Studio::Subprocess::TimeoutError, "process timed out after #{timeout}s: sonare"
    end

    error = assert_raises(Dilla::Reference::Error) do
      Studio::Subprocess.stub(:capture3, capture) do
        Dilla::Reference.capture!("libsonare", "sonare", "analyze", "track.wav", timeout: 0.25)
      end
    end

    assert_match(/libsonare timed out after 0.25s/, error.message)
    assert_match(/process timed out/, error.message)
  end

  def test_capture_preserves_exit_status_and_only_the_last_five_stderr_lines
    status = Object.new
    status.define_singleton_method(:success?) { false }
    status.define_singleton_method(:exitstatus) { 7 }
    stderr = (1..6).map { |number| "line #{number}\n" }.join
    capture = ->(*_command, timeout:, **_options) { ["", stderr, status] }

    error = assert_raises(Dilla::Reference::Error) do
      Studio::Subprocess.stub(:capture3, capture) do
        Dilla::Reference.capture!("Essentia", "streaming_extractor_music", timeout: 3)
      end
    end

    assert_match(/Essentia exited 7/, error.message)
    assert_includes error.message, "line 2"
    assert_includes error.message, "line 6"
    refute_includes error.message, "line 1"
  end

  def test_analysis_timeouts_scale_for_album_length_and_remain_bounded
    assert_equal 450, Dilla::Reference.analysis_timeout(900)
    assert_equal 3_600, Dilla::Reference.analysis_timeout(7_200)
    assert_equal 120, Dilla::Reference.analysis_timeout(1)
  end

  def test_source_metadata_preserves_youtube_identity_in_a_safe_allowlist
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "metadata.json"), JSON.generate(
        "source_type" => "youtube_audio", "id" => "XgObDlzrlUc",
        "title" => "Fantastic, Vol. 2", "channel" => "Slum Village",
        "url" => "https://www.youtube.com/watch?v=XgObDlzrlUc",
        "duration_seconds" => 4_492.0, "style_key" => "j_dilla",
        "cookies" => "must never be retained"
      ))

      source = Dilla::Reference.source_metadata(dir, "/private/path/source.wav")

      assert_equal "youtube_audio", source.fetch("source_type")
      assert_equal "Fantastic, Vol. 2", source.fetch("title")
      assert_equal 4_492.0, source.fetch("duration_seconds")
      refute source.key?("cookies")
      refute source.values.any? { |value| value.to_s.include?("/private/path") }
    end
  end

  def test_local_source_metadata_uses_only_the_filename
    source = Dilla::Reference.source_metadata("/tmp/no-metadata-here", "/private/path/demo.wav")

    assert_equal "local_audio", source.fetch("source_type")
    assert_equal "demo.wav", source.fetch("filename")
    refute source.values.any? { |value| value.to_s.include?("/private/path") }
  end

  def test_tempo_estimator_preserves_sub_eighty_bpm_grooves
    sample_rate = 40
    source_bpm = 70.0
    beat_samples = sample_rate * 60.0 / source_bpm
    samples = Array.new(sample_rate * 120, 0.0)
    position = 0.0
    while position < samples.size
      samples[position.round] = 1.0
      position += beat_samples
    end

    estimate = Dilla::Reference.estimate_tempo_samples(samples, sample_rate:)

    assert_in_delta source_bpm, estimate.fetch("bpm"), 2.0
    assert_operator estimate.fetch("bpm"), :<, 100.0
  end

  def test_tempo_segment_summary_reports_the_median_and_range
    segments = [
      { "bpm" => 92.0 }, { "bpm" => 94.0 }, { "bpm" => 96.0 }
    ]
    summary = Dilla::Reference.tempo_segment_summary(segments)

    assert_equal 3, summary.fetch("segment_count")
    assert_equal 94.0, summary.fetch("segment_median_bpm")
    assert_equal 4.0, summary.fetch("segment_bpm_range")
  end

  def test_dilla_profile_targets_the_local_tempo_median_for_a_long_reference
    mix = {
      "tempo" => { "bpm" => 140.0, "segment_median_bpm" => 94.0, "confidence" => 0.4 },
      "spectral_bands_db" => {}
    }

    profile = Dilla::Reference.profile_for(mix, style: "J Dilla")

    assert_equal 140.0, profile.fetch("measured_bpm")
    assert_equal 94, profile.fetch("target_bpm")
  end

  def test_rhythm_segment_summary_uses_the_median_to_limit_transition_outliers
    windows = [
      { "timing_spread_ms" => 9.0, "onset_density_per_bar" => 14.0, "offbeat_onset_share" => 0.5,
        "sixteenth_cell_ms" => 100.0, "sixteenth_grid_hits_per_bar" => Array.new(16, 1.0),
        "sixteenth_grid_strength_share" => Array.new(16, 0.01) },
      { "timing_spread_ms" => 12.0, "onset_density_per_bar" => 16.0, "offbeat_onset_share" => 0.7,
        "sixteenth_cell_ms" => 105.0, "sixteenth_grid_hits_per_bar" => Array.new(16, 2.0),
        "sixteenth_grid_strength_share" => Array.new(16, 0.02) },
      { "timing_spread_ms" => 80.0, "onset_density_per_bar" => 20.0, "offbeat_onset_share" => 0.95,
        "sixteenth_cell_ms" => 120.0, "sixteenth_grid_hits_per_bar" => Array.new(16, 20.0),
        "sixteenth_grid_strength_share" => Array.new(16, 0.9) }
    ]
    summary = Dilla::Reference.summarize_rhythm_segments(windows)

    assert_equal 3, summary.fetch("rhythm_window_count")
    assert_equal 12.0, summary.fetch("timing_spread_ms")
    assert_equal 16.0, summary.fetch("onset_density_per_bar")
    assert_equal 0.7, summary.fetch("offbeat_onset_share")
    assert_equal 105.0, summary.fetch("sixteenth_cell_ms")
    assert_equal Array.new(16, 2.0), summary.fetch("sixteenth_grid_hits_per_bar")
    assert_equal Array.new(16, 0.02), summary.fetch("sixteenth_grid_strength_share")
    assert_equal "mix_level_onset_proxy_not_drum_transcription", summary.fetch("grid_measurement")
  end

end
