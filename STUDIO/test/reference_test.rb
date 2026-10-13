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
end
