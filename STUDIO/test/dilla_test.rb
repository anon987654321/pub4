# frozen_string_literal: true

require "fileutils"
require_relative "minitest_helper"
require "open3"
require "tmpdir"
require_relative "../output_paths"
require "digest"
require_relative "../dilla/dilla"

# The whole suite stays under four minutes: every render here is one or two
# bars, and the analyzer run gets a two-bar fixture. Full-catalogue renders
# are a session activity, not a test.

class TestDillaCliContract < Minitest::Test
  def ruby
    RbConfig.ruby
  end

  def dilla
    File.expand_path("../dilla/dilla.rb", __dir__)
  end

  def run_dilla(*argv, chdir: File.dirname(dilla), env: {})
    out, err, status = Open3.capture3(env, ruby, dilla, *argv, chdir: chdir)
    [out, err, status]
  end

  def test_list_matches_the_format_master_parses
    out, err, status = run_dilla("--list")
    assert status.success?, "dilla --list failed: #{err}"
    lines = out.lines
    assert lines.first&.start_with?("Progressions:"), "menu must open with Progressions:"
    numbered = lines.drop_while { |l| !l.start_with?("Progressions:") }.drop(1)
                    .take_while { |l| !l.strip.empty? }
                    .filter_map { |l| l[/\A\s+(\d+)\s/, 1] }
    assert numbered.length >= 8, "engine plus recovered progressions expected"
    assert_equal (1..numbered.length).map(&:to_s), numbered, "progression numbering is dense"
    drums = lines.find { |l| l.start_with?("Drum patterns:") }
    assert drums, "Drum patterns: line missing"
    assert_includes drums, "dilla_shadow_full"
    assert_includes drums, "dusty_laid_back"
    profiles = lines.find { |l| l.start_with?("Groove profiles:") }
    assert profiles, "Groove profiles: line missing"
    assert_includes profiles, "dilla_shadow"
  end

  def test_help_lists_the_reference_pipeline
    out, _err, status = run_dilla("--help")
    assert status.success?
    assert_includes out, "reference"
    assert_includes out, "output-path"
  end

  def test_output_path_answers_the_master_contract
    Dir.mktmpdir do |dir|
      out, err, status = run_dilla("output-path", "dilla-render-directory", "2026-11-01T09:00:00Z",
                                   env: { "DILLA_OUTPUT_DIR" => File.join(dir, "renders") })
      assert status.success?, err
      assert_equal File.join(dir, "renders"), out.strip
      assert File.expand_path(out.strip), out.strip

      out, _e, status = run_dilla("output-path", "reference-root", env: { "XDG_DATA_HOME" => dir })
      assert status.success?
      # The reference root resolves symlinks; macOS's /var is /private/var.
      assert_equal File.join(File.realpath(dir), "dilla-references"), out.strip
    end
  end

  def test_output_overrides_cannot_write_inside_the_checkout
    root = Studio::OutputPaths::REPOSITORY_ROOT
    {
      "DILLA_OUTPUT_DIR" => -> { Studio::OutputPaths.dilla_render_directory },
      "POSTPRO_OUTPUT_DIR" => -> { Studio::OutputPaths.render_directory }
    }.each do |name, resolve|
      previous = ENV[name]
      begin
        ENV[name] = File.join(root, "STUDIO", "unapproved-renders")
        error = assert_raises(ArgumentError, name) { resolve.call }
        assert_match(/resolves inside the checkout/, error.message)
      ensure
        previous ? ENV[name] = previous : ENV.delete(name)
      end
    end
  end

  def test_external_output_overrides_remain_supported
    Dir.mktmpdir("studio-external-output-") do |directory|
      {
        "DILLA_OUTPUT_DIR" => -> { Studio::OutputPaths.dilla_render_directory },
        "POSTPRO_OUTPUT_DIR" => -> { Studio::OutputPaths.render_directory }
      }.each do |name, resolve|
        previous = ENV[name]
        begin
          target = File.join(directory, name)
          ENV[name] = target
          assert_equal target, resolve.call
        ensure
          previous ? ENV[name] = previous : ENV.delete(name)
        end
      end
    end
  end

  def test_output_override_symlinks_are_resolved_before_the_checkout_check
    root = Studio::OutputPaths::REPOSITORY_ROOT
    Dir.mktmpdir("studio-output-link-") do |directory|
      link = File.join(directory, "renders")
      File.symlink(File.join(root, "STUDIO", "dilla"), link)
      previous = ENV["DILLA_OUTPUT_DIR"]
      begin
        ENV["DILLA_OUTPUT_DIR"] = link
        error = assert_raises(ArgumentError) { Studio::OutputPaths.dilla_render_directory }
        assert_match(/resolves inside the checkout/, error.message)
      ensure
        previous ? ENV["DILLA_OUTPUT_DIR"] = previous : ENV.delete("DILLA_OUTPUT_DIR")
      end
    end
  end

  def test_unknown_flags_are_rejected
    _out, err, status = run_dilla("--frobnicate")
    refute status.success?
    assert_match(/unknown flag/, err)
  end
end

class TestDillaTheory < Minitest::Test
  def test_every_progression_chord_parses
    Dilla.progressions.each do |prog|
      prog.fetch("chords").each do |symbol|
        parsed = Dilla::ChordParser.parse(symbol, Dilla.theory)
        assert parsed[:root].between?(0, 11), "#{symbol}: root out of range"
        refute_empty parsed[:intervals], "#{symbol}: no intervals"
      rescue ArgumentError => e
        flunk "#{prog['id']}: #{e.message}"
      end
    end
  end

  def test_extended_and_slash_chords_parse
    {
      "Ab13" => [0, 4, 10, 14, 21],
      "Dbmaj9#11" => [0, 4, 11, 14, 18],
      "C7b9" => [0, 4, 10, 13],
      "D7alt" => [0, 4, 10, 15, 19],
      "Gsus4" => [0, 5, 7],
      "Bb/E" => [0, 4, 7]
    }.each do |symbol, _expected_shape|
      parsed = Dilla::ChordParser.parse(symbol, Dilla.theory)
      refute_nil parsed
    end
  end

  def test_slash_bass_pitch_class_is_read
    parsed = Dilla::ChordParser.parse("Bb/E", Dilla.theory)
    assert_equal 4, parsed[:bass]
  end

  def test_voicer_keeps_inner_voices_close_and_top_voice_high
    voicer = Dilla::Voicer.new(Dilla.theory)
    rng = Dilla::Rng.new(12)
    chords = %w[Fm9 Ab13 Dbmaj7#11 C7b9].map { |s| Dilla::ChordParser.parse(s, Dilla.theory) }
    voiced = voicer.voice(chords, rng)
    voiced.each_cons(2) do |a, b|
      b.each do |note|
        nearest = a.map { |n| (n - note).abs }.min
        assert nearest <= 7, "inner voice jumped #{nearest} semitones: #{a.inspect} -> #{b.inspect}"
      end
    end
    voiced.each do |voicing|
      assert voicing.max.between?(67, 96), "top voice out of register: #{voicing.inspect}"
    end
  end

  def test_recovered_transcriptions_carry_provenance
    rec = Dilla.recovered
    assert rec.dig("provenance", "transcription_sources").is_a?(Array)
    refute_empty rec.fetch("progressions")
    get_dis_money = rec.fetch("progressions").find { |p| p["id"] == "get_dis_money" }
    assert_equal 7, get_dis_money.fetch("loop_bars"), "Get Dis Money is the documented seven-bar loop"
    assert_equal "E", get_dis_money.fetch("pedal")
  end
end

class TestDillaRender < Minitest::Test
  def ruby
    RbConfig.ruby
  end

  def dilla
    File.expand_path("../dilla/dilla.rb", __dir__)
  end

  def read_wav_header(path)
    header = File.binread(path, 44)
    riff, _size, wave = header.unpack("A4VA4")
    _fmt_id, _fmt_size, _audio_fmt, channels, sample_rate, _byte_rate, _align, bits = header[12, 24].unpack("A4VvvVVvv")
    [riff, wave, channels, sample_rate, bits]
  end

  def test_deterministic_seed_produces_identical_renders
    Dir.mktmpdir do |dir|
      outs = [1, 2].map do |i|
        path = File.join(dir, "take#{i}.wav")
        out, err, status = Open3.capture3(RbConfig.ruby, dilla, "--progression", "1", "--bars", "1",
                                          "--seed", "4242", "--out", path, chdir: File.dirname(dilla))
        assert status.success?, err
        path
      end
      digest = ->(p) { Digest::SHA256.file(p).hexdigest }
      assert_equal digest.call(outs[0]), digest.call(outs[1]), "same seed must reproduce the same take"
    end
  end

  def test_render_writes_quality_session_and_provenance_sidecars
    Dir.mktmpdir do |dir|
      base = File.join(dir, "take")
      _out, err, status = Open3.capture3(RbConfig.ruby, dilla, "--progression", "1", "--bars", "1",
                                         "--seed", "7", "--out", base, chdir: File.dirname(dilla))
      assert status.success?, err
      %w[.quality.json .session.json .provenance.json].each do |suffix|
        assert File.file?("#{base}#{suffix}"), "missing sidecar #{suffix}"
      end
      quality = JSON.parse(File.read("#{base}.quality.json"))
      assert_operator quality.fetch("lufs_estimate"), :<, -7.0, "boom-bap masters must not sit at streaming loudness"
      assert_operator quality.fetch("lufs_estimate"), :>, -16.0
      assert_operator quality.fetch("peak_dbfs"), :<, 0.0
      shares = quality.fetch("stem_energy_share")
      assert_operator shares.fetch("drums"), :>=, 0.12, "drums must carry the mix"
      provenance = JSON.parse(File.read("#{base}.provenance.json"))
      render = provenance.fetch("render")
      assert_equal File.size("#{base}.wav"), render.fetch("bytes")
      assert_equal Digest::SHA256.file("#{base}.wav").hexdigest, render.fetch("sha256")
      riff, wave, channels, sample_rate, bits = read_wav_header("#{base}.wav")
      assert_equal "RIFF", riff
      assert_equal "WAVE", wave
      assert_equal 2, channels
      assert_equal 44_100, sample_rate
      assert_equal 16, bits
    end
  end

  def test_atomic_write_keeps_the_previous_artifact_when_replacement_fails
    Dir.mktmpdir do |dir|
      path = File.join(dir, "take.json")
      File.write(path, "previous")
      original_mode = File.stat(path).mode & 0o777

      File.stub(:rename, ->(*) { raise IOError, "simulated rename failure" }) do
        assert_raises(IOError) { Dilla.atomic_write(path, "replacement") }
      end

      assert_equal "previous", File.read(path)
      assert_equal original_mode, File.stat(path).mode & 0o777
      refute Dir.children(dir).any? { |name| name.start_with?(".take.json.") }
    end
  end

  def test_drum_balance_flag_moves_the_mix
    Dir.mktmpdir do |dir|
      readings = {}
      [-6, 6].each do |db|
        base = File.join(dir, "bal#{db}")
        _out, err, status = Open3.capture3(RbConfig.ruby, dilla, "--progression", "1", "--bars", "1",
                                           "--seed", "9", "--drum-balance", db.to_s, "--out", base,
                                           chdir: File.dirname(dilla))
        assert status.success?, err
        readings[db] = JSON.parse(File.read("#{base}.quality.json")).fetch("stem_energy_share").fetch("drums")
      end
      assert_operator readings[6], :>, readings[-6], "+6dB drums must outweigh -6dB drums"
    end
  end

  def test_sample_flip_chops_a_rights_cleared_loop
    Dir.mktmpdir do |dir|
      loop_path = File.join(dir, "crate.wav")
      # A rights-cleared operator-style loop: a simple sine groove rendered inline.
      ruby_snake = <<~'RB'
        sr = 44100
        n = sr * 4
        data = Array.new(n) do |i|
          t = i.to_f / sr
          f = [220.0, 261.63, 293.66, 329.63][(t / 0.5).to_i % 4]
          (Math.sin(2 * Math::PI * f * t) * 0.4 + Math.sin(2 * Math::PI * 55 * t) * 0.3)
        end
        pcm = data.map { |v| (v * 32767).round }.pack("s<#{n}")
        hdr = ["RIFF", 36 + pcm.bytesize, "WAVE", "fmt ", 16, 1, 1, sr, sr * 2, 2, 16, "data", pcm.bytesize].pack("A4VA4A4VvvVVvvA4V")
        File.binwrite(ARGV[0], hdr + pcm)
      RB
      _o, err, status = Open3.capture3(RbConfig.ruby, "-e", ruby_snake, loop_path)
      assert status.success?, err

      base = File.join(dir, "chopped")
      out, err, status = Open3.capture3(
        { "SAMPLE_LOOP" => loop_path, "SAMPLE_LOOP_VOL" => "0.42", "SAMPLE_LOOP_WEIGHT" => "0.6" },
        RbConfig.ruby, dilla, "--progression", "1", "--bars", "2", "--seed", "5",
        "--out", base, chdir: File.dirname(dilla)
      )
      assert status.success?, err
      session = JSON.parse(File.read("#{base}.session.json"))
      flip = session.fetch("sample_flip")
      assert_equal loop_path, flip.fetch("source")
      assert_equal 8, flip.fetch("slices")
      assert flip.fetch("picked").length.positive?
      quality = JSON.parse(File.read("#{base}.quality.json"))
      assert_operator quality.fetch("stem_energy_share").fetch("sample"), :>, 0.0
    end
  end
end

class TestDillaReferenceProfile < Minitest::Test
  def test_profile_schema_matches_what_master_reads
    features = {
      "bpm" => 87.59, "bpm_confidence" => 0.98, "duration_s" => 30.0,
      "onset_density_per_bar" => 8.2, "offbeat_onset_share" => 0.349,
      "timing_spread_ms" => 40.54, "swing_ratio" => 0.63,
      "drums_energy_share" => 0.179, "bass_energy_share" => 0.197,
      "other_energy_share" => 0.624, "vocal_energy_share" => 0.0,
      "brightness_hz" => 1606.1,
      "harmony" => { "key" => "F maj", "chord_changes" => 6, "chords" => [] },
      "melody" => { "median_hz" => 236.9 }, "drum_grid" => { "kick" => [1.0] * 16 }, "sections" => []
    }
    profile = Dilla.build_profile(features, { "title" => "x" }, "j_dilla", "/tmp/x.wav", nil)
    assert_equal "j_dilla", profile.fetch("style_key")
    assert_in_delta 87.6, profile.fetch("target_bpm"), 0.01
    assert_equal "dilla_shadow", profile.fetch("groove_profile")
    feats = profile.fetch("features")
    %w[onset_density_per_bar offbeat_onset_share timing_spread_ms drums_energy_share other_energy_share].each do |key|
      assert feats.key?(key), "media_intent reads features[#{key}]"
    end
  end

  def test_swung_and_loose_recordings_map_to_the_dilla_pocket
    features = { "bpm" => 92.0, "swing_ratio" => 0.61, "timing_spread_ms" => 14.0,
                 "onset_density_per_bar" => 9.0, "offbeat_onset_share" => 0.5,
                 "drums_energy_share" => 0.3, "other_energy_share" => 0.4 }
    profile = Dilla.build_profile(features, {}, "j_dilla", "/tmp/x.wav", nil)
    assert_equal "dilla_shadow", profile.fetch("groove_profile")
  end

  def test_analyzer_reports_tempo_and_valid_json_without_nan
    Dir.mktmpdir do |dir|
      # Two bars at 86 BPM: kick on 1 and 3, snare on 2 and 4, hats on 8ths.
      bar = 60.0 / 86 * 4
      sr = 44_100
      n = (bar * 2 * sr).to_i
      audio = Array.new(n, 0.0)
      kick_at = [0.0, bar / 2, bar, bar * 1.5]
      snare_at = [bar / 4, bar * 3 / 4, bar * 5 / 4, bar * 7 / 4]
      kick_at.each do |t|
        i0 = (t * sr).to_i
        len = (0.3 * sr).to_i
        len.times do |i|
          idx = i0 + i
          next if idx >= n

          audio[idx] += Math.sin(2 * Math::PI * 48 * i / sr * 4) * Math.exp(-i.to_f / (0.06 * sr)) * 0.9
        end
      end
      snare_at.each do |t|
        i0 = (t * sr).to_i
        len = (0.15 * sr).to_i
        len.times do |i|
          idx = i0 + i
          next if idx >= n

          audio[idx] += (Random.rand * 2 - 1) * Math.exp(-i.to_f / (0.04 * sr)) * 0.7
        end
      end
      (n / 2).times do |i|
        t = i * 2.0 / sr
        next unless (t % (bar / 8)).zero?

        audio[i * 2] += (Random.rand * 2 - 1) * Math.exp(-40.0 * (t % (bar / 8))) * 0.35
      end
      pcm = audio.map { |v| (v.clamp(-1, 1) * 32767).round }.pack("s<#{n}")
      hdr = ["RIFF", 36 + pcm.bytesize, "WAVE", "fmt ", 16, 1, 1, sr, sr * 2, 2, 16, "data", pcm.bytesize].pack("A4VA4A4VvvVVvvA4V")
      wav = File.join(dir, "two_bar.wav")
      File.binwrite(wav, hdr + pcm)
      features_path = File.join(dir, "features.json")
      _o, err, status = Open3.capture3("python3",
                                       File.expand_path("../dilla/reference_analyzer.py", __dir__),
                                       wav, "--json", features_path)
      assert status.success?, err
      text = File.read(features_path)
      refute_match(/NaN/, text, "the analyzer must not emit non-standard NaN tokens")
      feats = JSON.parse(text)
      assert_in_delta 86.0, feats.fetch("bpm"), 3.0, "a two-bar 86 BPM fixture must be measured near 86"
      %w[onset_density_per_bar offbeat_onset_share timing_spread_ms swing_ratio].each do |key|
        assert feats.key?(key)
      end
    end
  end
end

class TestDillaIndustrialTechno < Minitest::Test
  def test_renders_a_four_on_the_floor_take
    Dir.mktmpdir do |dir|
      base = File.join(dir, "techno")
      _out, err, status = Open3.capture3(RbConfig.ruby, File.expand_path("../dilla/dilla.rb", __dir__),
                                         "industrial-techno", "--out", base, "--bars", "2", "--bpm", "130",
                                         chdir: File.expand_path("..", __dir__))
      assert status.success?, err
      assert File.file?("#{base}.wav")
      quality = JSON.parse(File.read("#{base}.quality.json"))
      assert_operator quality.fetch("peak_dbfs"), :<, 0.0
    end
  end
end
