# frozen_string_literal: true

require_relative "test_helper"
require "json"
require "open3"
require "rbconfig"

# Dilla Lab is a standalone script (tools/dilla/dilla.rb) with top-level
# constants, so everything that needs the engine loaded runs in a subprocess
# — loading it here would leak ROOT/OUTPUT_DIR/etc. into the shared test
# process. The CLI dispatch is guarded by `__FILE__ == $PROGRAM_NAME`, so a
# subprocess `load` defines everything without executing a command.
class TestDillaLab < Minitest::Test
  ENGINE = File.expand_path("../tools/dilla/dilla.rb", __dir__)
  WRAPPER = File.expand_path("../tools/dilla.rb", __dir__)

  def eval_in_engine(script)
    probe = <<~RUBY
      $PROGRAM_NAME = "dilla_test_probe"
      load #{ENGINE.dump}
      require "json"
      #{script}
    RUBY
    out, err, status = Open3.capture3(RbConfig.ruby, "-e", probe)
    assert status.success?, "engine probe failed: #{err}"
    JSON.parse(out)
  end

  def test_every_grade_preset_fx_has_a_filter_implementation
    result = eval_in_engine(<<~RUBY)
      missing = GRADE_PRESETS.flat_map do |preset, config|
        stock = AUDIO_STOCKS.fetch(config.fetch(:stock))
        config.fetch(:fx).filter_map do |fx|
          filter = grade_filter(fx, stock)
          "\#{preset}/\#{fx}" if filter.nil? || filter.to_s.empty?
        end
      end
      puts JSON.generate(missing)
    RUBY
    assert_empty result, "GRADE_PRESETS reference fx with no grade_filter arm (silent no-op)"
  end

  def test_every_audio_stock_has_the_full_parameter_set
    result = eval_in_engine(<<~RUBY)
      required = %i[noise_amp sat_drive rolloff_hz wow_rate wow_depth warmth_db]
      missing = AUDIO_STOCKS.flat_map do |name, params|
        (required - params.keys).map { |key| "\#{name}.\#{key}" }
      end
      puts JSON.generate(missing)
    RUBY
    assert_empty result, "AUDIO_STOCKS entries missing parameters grade_filter reads"
  end

  def test_commands_list_matches_dispatch_table_and_aliases_resolve
    result = eval_in_engine(<<~RUBY)
      puts JSON.generate(
        commands: COMMANDS,
        dispatch_keys: DISPATCH.keys,
        alias_keys: COMMAND_ALIASES.keys,
        bad_aliases: COMMAND_ALIASES.reject { |_, target| DISPATCH.key?(target) }.keys
      )
    RUBY
    expected = (result.fetch("dispatch_keys") + result.fetch("alias_keys")).sort
    assert_equal expected, result.fetch("commands").sort
    assert_empty result.fetch("bad_aliases"), "aliases pointing at nonexistent commands"
  end

  def test_apply_voicing_returns_bounded_playable_chords_for_every_style
    result = eval_in_engine(<<~RUBY)
      hz = [174.61, 207.65, 261.63, 311.13] # Fm7
      bad = %i[quartal drop2 drop3 spread cluster].filter_map do |style|
        voiced = apply_voicing(hz, style)
        ok = voiced.is_a?(Array) && voiced.length.between?(1, 5) &&
             voiced.all? { |v| v.is_a?(Float) && v.positive? } && voiced == voiced.uniq
        style unless ok
      end
      puts JSON.generate(bad)
    RUBY
    assert_empty result, "apply_voicing styles returning unplayable/unbounded output"
  end

  def test_unknown_cli_flag_aborts_with_the_known_flag_list
    _out, err, status = Open3.capture3(RbConfig.ruby, ENGINE, "--bogus=1", "help")
    refute status.success?, "unknown flag should abort, not run"
    assert_includes err, "unknown flag --bogus"
    assert_includes err, "--track"
  end

  def test_cli_flags_reach_env_before_dispatch
    result = eval_in_engine(<<~RUBY)
      apply_flags!(["--track=timeless", "positional", "--bars=8"])
      puts JSON.generate(track: ENV["TRACK"], bars: ENV["BARS"])
    RUBY
    assert_equal "timeless", result.fetch("track")
    assert_equal "8", result.fetch("bars")
  end

  def test_groove_score_rewards_pocket_density_and_timing_bias
    result = eval_in_engine(<<~RUBY)
      sparse = {
        kick: [[0, 0.8], [1, 0.7]], snare: [[0.5, 0.62]], ghost: [[0.3, 0.28]],
        hat: [[0.1, 0.4], [0.2, 0.38]],
        _groove_meta: { snare_early_ms: [-4], hat_late_ms: [2], ghost_vel: [0.28] }
      }
      pocket = {
        kick: [[0, 0.82], [0.75, 0.7], [1.5, 0.68]], snare: [[0.5, 0.66], [1.0, 0.58]],
        ghost: [[0.25, 0.22], [0.35, 0.36], [0.55, 0.31], [0.7, 0.29]],
        hat: (0..7).map { |i| [i * 0.1, 0.42] },
        _groove_meta: { snare_early_ms: [-14, -11], hat_late_ms: [9, 7, 8], ghost_vel: [0.22, 0.36, 0.31, 0.29] }
      }
      puts JSON.generate(
        sparse: DillaGrooveScore.analyze(sparse)[:score],
        pocket: DillaGrooveScore.analyze(pocket)[:score]
      )
    RUBY
    assert_operator result.fetch("pocket"), :>, result.fetch("sparse"),
                   "pocket-heavy schedule should outscore sparse kicks-only grid"
  end

  def test_pad_layers_stay_held_and_arp_routes_to_lead_cfg
    result = eval_in_engine(<<~RUBY)
      pads = [[0.0, 0.9, { name: "Fm9", hz: [174.61, 261.63] }, 3.8]]
      cfg = { bpm: 94, swing: 57, track: :erykah_minor }
      patch = { id: :prophet_5_pad, arp_styles: %i[updown pingpong] }
      ENV["PAD_ARP_MODE"] = "wash"
      ENV["LEAD_ARP"] = "0"
      held = pad_midi_events_for_layer(pads, cfg, patch, role: :ep, duration: 16)
      lead_cfg = lead_arp_cfg_for(patch)
      puts JSON.generate(
        held_only: held == pads,
        lead_enabled: lead_arp_enabled?,
        lead_style: lead_cfg&.dig(:style),
        lead_subdiv: lead_cfg&.dig(:subdiv)
      )
    RUBY
    assert result.fetch("held_only"), "pad layers must stay held — no chord-layer arp"
    assert result.fetch("lead_enabled"), "non-held PAD_ARP_MODE must enable lead arp"
    assert_equal "pingpong", result.fetch("lead_style").to_s
    assert_equal 4, result.fetch("lead_subdiv"), "wash PAD_ARP_MODE maps to soul_wash lead preset"
  end

  def test_lead_morph_xlead_varies_patches_and_arp
    result = eval_in_engine(<<~RUBY)
      ENV["LEAD_MORPH"] = "1"
      ENV["SYNTH_MORPH"] = "1"
      ENV["LEAD_MORPH_VOICE"] = "hard"
      patches = 8.times.map { |i| morph_lead_patch_for_chord(i)&.dig(:id) }.compact.uniq
      arp_styles = 8.times.map { |i| morph_lead_arp_cfg_for_chord(i, synth_patch_by_id(:saw_lead))[:style] }.uniq
      voices = 6.times.map do |i|
        @stream_iterate_count = i
        stream_iterate_morph_synth!
        ENV["LEAD_MORPH_VOICE"]
      end
      puts JSON.generate(patch_count: patches.length, arp_count: arp_styles.length, voices: voices.uniq)
    RUBY
    assert_operator result.fetch("patch_count"), :>=, 3, "xlead should morph lead patches per chord"
    assert_operator result.fetch("arp_count"), :>=, 3, "xlead should morph arp figures per chord"
    assert_operator result.fetch("voices").length, :>=, 3, "stream should rotate lead morph voices"
  end

  def test_fm_native_ratio_pool_velocity_and_morph_expr
    result = eval_in_engine(<<~RUBY)
      ENV["FM_NATIVE"] = "1"
      ratios = 8.times.map { |i| fm_ratio_for_chord(i)[:m] }.uniq
      irrational = FM_RATIO_POOL.count { |r| r[:irrational] }
      idx_soft = fm_index_from_velocity(0.3, base_index: 2.0, role: :xlead)
      idx_hard = fm_index_from_velocity(0.9, base_index: 2.0, role: :xlead)
      morph = fm_mod_ratio_expr(1.37, 1.0, 8.0, irrational: true)
      body = native_fm_waveform_body(220.0, index_expr: "(2.1)*exp(-t*0.3)", mod_ratio_expr: "2")
      puts JSON.generate(
        ratio_count: ratios.length,
        irrational: irrational,
        idx_soft: idx_soft,
        idx_hard: idx_hard,
        morph: morph,
        body_includes_phase: body.include?("sin(2*PI*220"),
        fm_enabled: fm_native_enabled?
      )
    RUBY
    assert result.fetch("fm_enabled"), "FM_NATIVE should be enabled in soul stream defaults"
    assert_operator result.fetch("ratio_count"), :>=, 4, "FM ratio pool should vary per chord"
    assert_operator result.fetch("irrational"), :>=, 2, "pool should include irrational→rational morph ratios"
    assert_operator result.fetch("idx_hard"), :>, result.fetch("idx_soft"), "velocity should raise mod index"
    assert_includes result.fetch("morph"), "1.37", "irrational ratio should morph toward integer target"
    assert result.fetch("body_includes_phase"), "native FM body should use phase-modulated carrier"
  end

  def test_synth_morph_cycles_voices_and_patches_per_chord
    result = eval_in_engine(<<~RUBY)
      ENV["SYNTH_MORPH"] = "1"
      ENV["SYNTH_CYCLE"] = "1"
      ENV["PAD_VOICE"] = "blend"
      @stream_iterate_count = 0
      voices = 4.times.map do |i|
        @stream_iterate_count = i
        stream_iterate_morph_synth!
        ENV["PAD_VOICE"]
      end
      ep_ids = 8.times.map { |i| morph_patch_for_chord(i, role: :ep)&.dig(:id) }.compact.uniq
      warm_ids = 8.times.map { |i| morph_patch_for_chord(i, role: :warm)&.dig(:id) }.compact.uniq
      puts JSON.generate(voices: voices.uniq, ep_count: ep_ids.length, warm_count: warm_ids.length)
    RUBY
    assert_operator result.fetch("voices").length, :>=, 3, "stream morph should rotate pad voice families"
    assert_operator result.fetch("ep_count"), :>=, 3, "per-chord EP morph should vary presets"
    assert_operator result.fetch("warm_count"), :>=, 3, "per-chord warm morph should vary presets"
  end

  def test_synth_cycle_picks_from_expanded_voice_pools
    result = eval_in_engine(<<~RUBY)
      ENV["SYNTH_CYCLE"] = "1"
      ENV["PAD_VOICE"] = "blend"
      ENV["LEAD_VOICE"] = "soul_prophet"
      picks = 12.times.map do |i|
        apply_pad_voice_preset!(seed: i * 997)
        apply_lead_voice_preset!(seed: i * 997)
        [@render_ep_patch&.dig(:id), @render_warm_patch&.dig(:id), @render_lead_patch&.dig(:id)]
      end
      ep_ids = picks.map(&:first).compact.uniq
      warm_ids = picks.map { |p| p[1] }.compact.uniq
      lead_ids = picks.map(&:last).compact.uniq
      puts JSON.generate(
        ep_count: ep_ids.length,
        warm_count: warm_ids.length,
        lead_count: lead_ids.length,
        ep_pool: PATCH_CYCLE_EP[:blend].length,
        lead_pool: LEAD_VOICE_POOLS[:soul_prophet].length
      )
    RUBY
    assert_operator result.fetch("ep_count"), :>=, 3, "blend EP cycle should vary across renders"
    assert_operator result.fetch("warm_count"), :>=, 3, "blend warm cycle should vary across renders"
    assert_operator result.fetch("lead_count"), :>=, 2, "soul_prophet lead cycle should vary"
    assert_operator result.fetch("ep_pool"), :>, 8
    assert_operator result.fetch("lead_pool"), :>, 2
  end

  def test_electronium_loop_profile_resolves_in_engine
    result = eval_in_engine(<<~RUBY)
      ENV["TRACK"] = "electronium_loop"
      ENV["DILLA_RAW"] = "1"
      pads = dilla_progression(:electronium_loop)
      names = pads.map { |c| c[:name] }
      curated, = DillaHarmony.beautify_curated_pipeline(pads, enhanced_resolve_config, phases: [])
      bad = curated.reject { |ch| DillaHarmony.chord_tones_preserved?(ch) }.map { |ch| ch[:name] }
      puts JSON.generate(names: names, bad: bad, progression: DillaElectronium::PROGRESSION.map(&:to_s))
    RUBY
    assert_includes result.fetch("names"), "Fm9"
    assert_includes result.fetch("names"), "Dbmaj9"
    assert_empty result.fetch("bad")
  end

  def test_groove_score_evolve_recommendations_nudge_low_pocket
    result = eval_in_engine(<<~RUBY)
      sparse = {
        kick: [[0, 0.8], [0.75, 0.7], [1.5, 0.68], [2.25, 0.65]],
        snare: [[0.5, 0.62]], ghost: [],
        hat: [[0.1, 0.4]], _groove_meta: { snare_early_ms: [2], hat_late_ms: [1], ghost_vel: [0.28] }
      }
      recs = DillaGrooveScore.evolve_recommendations(DillaGrooveScore.analyze(sparse))
      puts JSON.generate(
        ghost_tier: recs[:ghost_tier].to_s,
        snare_early: recs[:snare_early],
        swing_delta: recs[:swing_delta]
      )
    RUBY
    assert_equal "accent", result.fetch("ghost_tier")
    assert result.fetch("snare_early")
    assert_operator result.fetch("swing_delta"), :>=, 1.0
  end

  def test_ghost_tier_and_slash_bass_wiring
    result = eval_in_engine(<<~RUBY)
      ENV["GHOST_TIER"] = "accent"
      ENV["SLASH_BASS"] = "1"
      ENV["TRACK"] = "syncopated_slash_ninth"
      ENV["DILLA_RAW"] = "1"
      cfg = enhanced_resolve_config
      pads = dilla_progression(cfg[:progression])
      bass = slash_bass_pads_for(pads, cfg)
      tier = ghost_tier_for(8, :build)
      puts JSON.generate(
        slash_enabled: slash_bass_enabled?(cfg),
        bass_len: bass&.length,
        bass_pedal: bass&.first&.dig(:hz)&.min&.round(1),
        tier: tier.to_s
      )
    RUBY
    assert result.fetch("slash_enabled")
    assert_operator result.fetch("bass_len"), :>, 0
    assert_equal "accent", result.fetch("tier")
  end

  def test_profile_mash_blends_harmony_and_drum_feel
    result = eval_in_engine(<<~RUBY)
      ENV["PROFILE_MASH"] = "maj7_minor_cycle+electronium_loop"
      ENV["DILLA_RAW"] = "1"
      cfg = apply_profile_mash!(enhanced_resolve_config)
      puts JSON.generate(
        progression: cfg[:progression].to_s,
        feel: cfg[:feel].to_s,
        mashed: cfg[:mashed]
      )
    RUBY
    assert_equal "maj7_minor_cycle", result.fetch("progression")
    assert result.fetch("mashed")
    assert_equal "maj7_minor_cycle", result.fetch("mashed").fetch("harmony")
    assert_equal "electronium_loop", result.fetch("mashed").fetch("drums")
  end

  def test_render_mode_sketch_defaults
    result = eval_in_engine(<<~RUBY)
      %w[STEM_EXPORT COMPOSITION RENDER_BEAUTY_MIN LISTEN_PASSES].each { |k| ENV.delete(k) }
      ENV["RENDER_MODE"] = "sketch"
      ENV["DILLA_RAW"] = "0"
      ENV["DILLA_STREAMING"] = "1"
      apply_render_mode!
      puts JSON.generate(
        stem_export: ENV["STEM_EXPORT"],
        composition: ENV["COMPOSITION"],
        beauty_min: ENV["RENDER_BEAUTY_MIN"]
      )
    RUBY
    assert_equal "0", result.fetch("stem_export")
    assert_equal "0", result.fetch("composition")
    assert_equal "55", result.fetch("beauty_min")
  end

  def test_flylo_camel_learned_drum_grid_registers
    result = eval_in_engine(<<~RUBY)
      remove_instance_variable(:@learned_engine_cache) if instance_variable_defined?(:@learned_engine_cache)
      grid = flylo_drum_grid_for("quartal_west_coast")
      ENV["TRACK"] = "quartal_west_coast"
      kicks = learned_flylo_overlay_steps(:kicks)
      snares = learned_flylo_overlay_steps(:snares)
      puts JSON.generate(
        bpm: grid&.dig("bpm"),
        builtin: grid["flylo_kicks"] == FLYLO_CAMEL_DRUM_GRID["flylo_kicks"],
        kicks: kicks,
        snares: snares,
        kick_count: kicks&.length,
        syncopated: kicks&.any? { |s| s.odd? }
      )
    RUBY
    assert_equal 86, result.fetch("bpm")
    assert result.fetch("builtin"), "Camel grid should be baked into dilla.rb"
    assert_operator result.fetch("kick_count"), :>=, 4
    assert result.fetch("syncopated"), "Camel grid should include off-beat kick steps"
    assert_includes result.fetch("kicks"), 3
  end

  def test_camel_mode_applies_defaults_and_grid
    result = eval_in_engine(<<~RUBY)
      ENV["DILLA_STREAMING"] = "1"
      remove_instance_variable(:@learned_engine_cache) if instance_variable_defined?(:@learned_engine_cache)
      apply_camel_profile!(force: true)
      grid = flylo_drum_grid_for(ENV["TRACK"])
      puts JSON.generate(
        mode: ENV["RENDER_MODE"],
        track: ENV["TRACK"],
        bpm: ENV["BPM"],
        kicks: ENV["KICKS"],
        rap: ENV["RAP_VOCAL"],
        la_beat: la_beat_progression_enabled?,
        form: ENV["FORM"],
        groove: ENV["GROOVE_DNA"],
        performer: ENV["PERFORMER"],
        stream_track: ENV["STREAM_TRACK"],
        pocket_drums: dilla_pocket_drums_enabled?,
        kicks_enabled: kicks_enabled?,
        grid_bpm: grid&.dig("bpm"),
        flylo_kicks: grid&.dig("flylo_kicks"),
        progression: load_learned_engine.dig("progressions", ENV["TRACK"])&.length
      )
    RUBY
    assert_equal "camel", result.fetch("mode")
    assert_equal "chromatic_mediant_drift", result.fetch("track")
    assert_equal "86", result.fetch("bpm")
    assert_equal "1", result.fetch("kicks"), "Hybrid pocket + FlyLo so drums stay audible"
    assert_equal "j_dilla", result.fetch("rap")
    assert_nil result.fetch("stream_track"), "Camel mode should rotate — no STREAM_TRACK pin"
    assert result.fetch("la_beat")
    assert_equal "camel_32", result.fetch("form")
    assert_equal "wonky", result.fetch("groove")
    assert_equal "glasper", result.fetch("performer")
    assert result.fetch("pocket_drums"), "Pocket drums stay on unless FLYLO_DRUMS_ONLY=1"
    assert result.fetch("kicks_enabled"), "Kicks enabled under hybrid Camel kit"
    assert_equal 86, result.fetch("grid_bpm")
    assert_equal [3, 7, 9, 11, 13, 15], result.fetch("flylo_kicks")
    assert_operator result.fetch("progression"), :>=, 8
  end

  def test_la_beat_progression_varies_chords_and_lengths
    result = eval_in_engine(<<~RUBY)
      ENV["LA_BEAT_PROGRESSION"] = "1"
      ENV["LINEAR_CHORD_INDEX"] = "1"
      ENV["TRACK"] = "maj7_minor_cycle"
      ENV["DILLA_RAW"] = "1"
      cfg = enhanced_resolve_config
      n_bars = 32
      needed = (n_bars.to_f / cfg[:chord_bars]).ceil + 1
      pads = dilla_progression(cfg[:progression])
      arranged, phases, lens = arrange_la_beat_progression(pads, needed, cfg)
      names = arranged.map { |c| c[:name] }
      beat_p = 60.0 / cfg[:bpm]
      @render_chord_bar_lens = lens
      ENV["FLYLO_DRUM_OVERLAY"] = "1"
      events = dilla_schedule(n_bars, beat_p, arranged, chord_bars: cfg[:chord_bars],
                              phrase_bars: cfg[:phrase_bars], swing: cfg[:swing], feel: cfg[:feel],
                              timing: cfg[:timing], quintuplet: cfg[:quintuplet], chord_phases: phases)
      pad_names = events[:pad].map { |e| e[2][:name] }
      indices = (0...n_bars).map { |b|
        dilla_chord_index(b, arranged, chord_bars: cfg[:chord_bars], phrase_bars: cfg[:phrase_bars],
                          chord_bar_lens: lens)
      }
      puts JSON.generate(
        chord_count: names.length,
        unique_names: names.uniq.length,
        lens_variety: lens.uniq.length,
        pad_events: events[:pad].length,
        pad_unique: pad_names.uniq.length,
        index_unique: indices.uniq.length,
        flylo_kick: events[:flylo_kick]&.length || 0
      )
    RUBY
    assert_operator result.fetch("chord_count"), :>=, 12
    assert_operator result.fetch("unique_names"), :>=, 5
    assert_operator result.fetch("lens_variety"), :>=, 2
    assert_operator result.fetch("pad_unique"), :>=, 4
    assert_operator result.fetch("index_unique"), :>=, 5
    assert_operator result.fetch("flylo_kick"), :>, 0
  end

  def test_dilla_neosoul_aydin_bach_progressions_resolve
    %i[maj7_minor_cycle neo_soul electronium_loop aydin_modal_quartal aydin_jazz_turn
       bach_circle_descent bach_descending_bass].each do |track|
      result = eval_in_engine(<<~RUBY)
        ENV["TRACK"] = #{track.to_s.dump}
        ENV["DILLA_RAW"] = "1"
        pads = dilla_progression(#{track.inspect})
        names = pads.map { |c| c[:name] }
        puts JSON.generate(track: #{track.to_s.dump}, count: names.length, names: names)
      RUBY
      assert_operator result.fetch("count"), :>=, 4, "#{track} should resolve at least 4 chords"
      assert_equal result.fetch("count"), result.fetch("names").length
    end
  end

  def test_curated_progression_preserves_chord_tones_through_voice_lead
    result = eval_in_engine(<<~RUBY)
      ENV["TRACK"] = "maj7_minor_cycle"
      ENV["DILLA_RAW"] = "1"
      pads = dilla_progression(:maj7_minor_cycle)
      cfg = enhanced_resolve_config
      curated, = DillaHarmony.beautify_curated_pipeline(pads, cfg, phases: [])
      bad = curated.reject { |ch| DillaHarmony.chord_tones_preserved?(ch) }.map { |ch| ch[:name] }
      puts JSON.generate(bad: bad, sample: curated.first&.dig(:name))
    RUBY
    assert_empty result.fetch("bad"), "curated pipeline scrambled chord tones: #{result.fetch('bad')}"
  end

  def test_curated_progression_beautify_preserves_harmonic_quality
    result = eval_in_engine(<<~RUBY)
      ENV["TRACK"] = "erykah_minor"
      ENV["DILLA_RAW"] = "1"
      pads = dilla_progression(:erykah_minor)
      cfg = enhanced_resolve_config
      curated, = DillaHarmony.beautify_curated_pipeline(pads, cfg, phases: [])
      full, = DillaHarmony.beautify_pipeline(pads, cfg, phases: [])
      puts JSON.generate(
        curated_beauty: DillaHarmony.score_beauty(curated),
        full_beauty: DillaHarmony.score_beauty(full),
        curated_len: curated.length,
        full_len: full.length
      )
    RUBY
    assert_operator result.fetch("curated_beauty"), :>=, 72
    assert_operator result.fetch("curated_beauty"), :>=, result.fetch("full_beauty"),
                   "curated pipeline should not score below aggressive reharm path"
    assert_operator result.fetch("curated_len"), :<=, result.fetch("full_len") + 2,
                   "curated path should not inject turnaround/extra dominants"
  end

  def test_lead_voice_and_arp_mode_presets_resolve
    result = eval_in_engine(<<~RUBY)
      ENV["SYNTH_CYCLE"] = "0"
      ENV["LEAD_VOICE"] = "erykah"
      ENV["LEAD_ARP_MODE"] = "soul_wash"
      ENV["LEAD_ARP"] = "1"
      apply_lead_voice_preset!
      patch = @render_lead_patch
      cfg = lead_arp_cfg_for({ arp_styles: %i[updown] })
      arp_mode = lead_arp_mode
      preset_key = lead_arp_preset_key
      ENV.delete("LEAD_VOICE")
      ENV.delete("LEAD_ARP_MODE")
      apply_track_soul_profile!(:erykah_minor)
      puts JSON.generate(
        voice_id: patch&.dig(:id),
        arp_mode: arp_mode,
        preset_key: preset_key,
        lead_style: cfg&.dig(:style),
        lead_subdiv: cfg&.dig(:subdiv),
        track_voice: ENV["LEAD_VOICE"],
        track_arp: ENV["LEAD_ARP_MODE"]
      )
    RUBY
    assert_equal "erykah_dust_lead", result.fetch("voice_id").to_s
    assert_equal "soul_wash", result.fetch("arp_mode").to_s
    assert_equal "soul_wash", result.fetch("preset_key").to_s
    assert_equal "pingpong", result.fetch("lead_style").to_s
    assert_equal 4, result.fetch("lead_subdiv")
    assert_equal "erykah", result.fetch("track_voice")
    assert_equal "erykah_dust", result.fetch("track_arp")
  end

  def test_music_gems_coltrane_parses_dilla_chord_symbols
    result = eval_in_engine(<<~RUBY)
      DillaMusicGems.bootstrap!
      ch = DillaMusicGems.chord_from_symbol("Fm9")
      analysis = DillaMusicGems.progression_analysis(%w[Dbmaj9 Cm9 Fm9 Bbm9])
      puts JSON.generate(
        gems: DillaMusicGems.status,
        fm9_hz: ch&.dig(:hz),
        analysis_notation: analysis&.dig(:notation)
      )
    RUBY
    assert result.fetch("gems").values.any?, "expected at least one :dilla gem to load"
    hz = result.fetch("fm9_hz")
    assert hz.is_a?(Array) && hz.length >= 4
    assert hz.any? { |f| (f - 174.61).abs < 2.0 }, "Fm9 voicing should include F3 (~174 Hz)"
    assert result.fetch("analysis_notation").to_s.include?("-"), "Donuts loop should yield roman notation"
  end

  def test_source_learn_compose_report_maps_stems_to_engine_hints
    result = eval_in_engine(<<~RUBY)
      DillaMusicGems.bootstrap!
      stem_analysis = {
        "drums.wav" => { bpm_estimate: 86.0 },
        "piano.wav" => {
          pitch_classes: [5, 8, 0, 3],
          top_chords: [{ name: "Fm9", score: 0.42 }, { name: "Bbm9", score: 0.38 }],
          coltrane_candidates: [{ name: "Fm9", overlap: 4 }]
        }
      }
      report = DillaSourceLearn.compose_report(
        source: "fixture",
        stem_dir: "/tmp/stems",
        stem_analysis: stem_analysis,
        full_analysis: { bpm_estimate: 86.0 }
      )
      puts JSON.generate(
        bpm: report[:bpm_estimate],
        symbols: report[:progression_symbols],
        track: report[:engine_hints][:track],
        voicing: report[:engine_hints][:voicing]
      )
    RUBY
    assert_in_delta 86.0, result.fetch("bpm"), 0.1
    assert result.fetch("symbols").any? { |s| s.to_s.include?("Fm") }
    assert_equal "minor_iv_loop", result.fetch("track").to_s
    assert result.fetch("voicing").to_s.length.positive?
  end

  def test_analog_wild_chain_resolves_and_builds_grade_filters
    result = eval_in_engine(<<~RUBY)
      rng = Random.new(42)
      name = build_random_wild_analog_chain!(rng)
      cfg = analog_chain_lookup(name)
      stock = AUDIO_STOCKS[cfg[:stock]]
      missing = cfg[:fx].filter_map do |fx|
        f = grade_filter(fx, stock)
        fx if f.nil? || f.to_s.empty?
      end
      filt = analog_emulation_filters("in", name, out_tag: "out")
      puts JSON.generate(
        name: name.to_s,
        fx_count: cfg[:fx].length,
        missing: missing,
        filter_segments: filt.length
      )
    RUBY
    assert result.fetch("name").start_with?("wild_")
    assert_operator result.fetch("fx_count"), :>=, 5
    assert_empty result.fetch("missing")
    assert_operator result.fetch("filter_segments"), :>=, 2
  end

  def test_form_section_map_and_harmony_lead_tones
    result = eval_in_engine(<<~RUBY)
      ENV["FORM"] = "soul_16"
      remove_instance_variable(:@resolve_form_map) if instance_variable_defined?(:@resolve_form_map)
      sections = (0...16).map { |b| form_section_at(b, 16) }
      chord = { name: "Fm9", hz: [174.61, 207.65, 261.63, 311.13, 392.0] }
      prev = { name: "Cm9", hz: [130.81, 155.56, 196.0, 233.08, 311.13] }
      tones = DillaHarmonyLead.harmonic_arp_tones_for_chord(chord, prev_chord: prev, mode: :hybrid)
      ENV["MOTIF_RECALL"] = "1"
      @chord_motif_cache = {}
      m1 = chord_motif_for(chord)
      m2 = chord_motif_for(chord)
      puts JSON.generate(
        sections: sections,
        tone_count: tones.length,
        motif_stable: m1 == m2,
        harmony_lead_default: harmony_lead_enabled? == false
      )
    RUBY
    assert_equal %i[intro intro intro intro main main main main main main main main build build build build],
                 result.fetch("sections").map(&:to_sym)
    assert_operator result.fetch("tone_count"), :>=, 4
    assert result.fetch("motif_stable")
  end

  def test_long_soul_render_mode_sets_form_and_harmony_lead
    result = eval_in_engine(<<~RUBY)
      %w[FORM HARMONY_LEAD TRACK VOICING RENDER_MODE].each { |k| ENV.delete(k) }
      ENV["DILLA_STREAMING"] = "1"
      ENV["RENDER_MODE"] = "long_soul"
      apply_render_mode!
      puts JSON.generate(
        form: ENV["FORM"],
        harmony_lead: ENV["HARMONY_LEAD"],
        track: ENV["TRACK"],
        voicing: ENV["VOICING"]
      )
    RUBY
    assert_equal "soul_32", result.fetch("form")
    assert_equal "1", result.fetch("harmony_lead")
    assert_equal "long_soul", result.fetch("track")
    assert_equal "bill_evans", result.fetch("voicing")
  end

  def test_soul_progression_resolves_extended_chord_symbols
    result = eval_in_engine(<<~RUBY)
      %w[Abmaj9low Bb7sus C7b9 Fm/C].each do |sym|
        ch = DillaLofiMachine.chord_from_symbol(sym)
        abort "missing " + sym unless ch && ch[:hz]&.length.to_i >= 4
      end
      ENV["TRACK"] = "fourth_third_sixth_second_turn"
      pads = dilla_progression(:fourth_third_sixth_second_turn)
      names = pads.map { |c| c[:name].to_s }
      puts JSON.generate(count: pads.length, names: names, distinct: names.uniq.length)
    RUBY
    assert_operator result.fetch("count"), :>=, 6
    assert_operator result.fetch("distinct"), :>=, 4
    assert_includes result.fetch("names"), "Abmaj9low"
  end

  def test_drum_step_grid_from_wav_returns_steps
    result = eval_in_engine(<<~RUBY)
      require "tempfile"
      require "open3"
      tmp = Tempfile.new(["grid", ".wav"])
      tmp.close
      Open3.capture2e("ffmpeg", "-y", "-f", "lavfi", "-i", "sine=frequency=100:duration=2", "-ar", "44100", "-ac", "2", tmp.path)
      grid = drum_step_grid_from_wav(tmp.path, bpm: 90)
      puts JSON.generate(has_grid: grid&.dig(:step_grid).is_a?(Hash), bpm: grid&.dig(:bpm_estimate))
    RUBY
    assert result.fetch("has_grid")
    assert_equal 90, result.fetch("bpm")
  end

  def test_learn_promote_writes_engine_file
    result = eval_in_engine(<<~RUBY)
      DillaSourceLearn.ensure_dir!
      DillaSourceLearn.save_playlist_entry!({
        id: "promo_test", artist: "T", title: "X",
        progression_symbols: %w[Dbmaj9 Cm9 Fm9 Bbm9 Ebmaj9 Abmaj9low],
        copyable_dna: { harmony: { progression: %w[Dbmaj9 Cm9 Fm9 Bbm9 Ebmaj9 Abmaj9low] },
                        drums: { kicks: [0, 6, 10], snares: [4, 12], bpm: 88 },
                        engine: { track: "fourth_third_sixth_second_turn" } },
        engine_hints: { track: "fourth_third_sixth_second_turn" }
      })
      ENV["DILLA_QUIET"] = "1"
      out = learn_promote!
      eng = load_learned_engine(refresh: true)
      puts JSON.generate(
        promoted: out[:promoted],
        has_prog: eng.dig("progressions", "learned_promo_test")&.length.to_i >= 4
      )
    RUBY
    assert_operator result.fetch("promoted"), :>=, 1
    assert result.fetch("has_prog")
  end

  def test_playlist_catalog_helpers_round_trip
    result = eval_in_engine(<<~RUBY)
      DillaSourceLearn.ensure_dir!
      entry = { id: "test_slug", artist: "Test", title: "Track", copyable_dna: { drums: { kicks: [0, 8] } } }
      paths = DillaSourceLearn.save_playlist_entry!(entry)
      cat = DillaSourceLearn.load_playlist_catalog
      hit = cat["tracks"].find { |t| t["id"] == "test_slug" }
      puts JSON.generate(saved: !hit.nil?, catalog: paths[:catalog])
    RUBY
    assert result.fetch("saved")
  end

  def test_gospel_biii_profile_lookup_after_normalize
    result = eval_in_engine(<<~RUBY)
      entry = DillaLofiMachine.profile_entry(:gospel_bIII)
      puts JSON.generate(found: !entry.nil?, chords: entry&.dig(:chords))
    RUBY
    assert result.fetch("found")
    assert_operator result.fetch("chords").length, :>=, 2
  end

  def test_rap_vocal_resolve_sirkel_sag_slug
    result = eval_in_engine(<<~RUBY)
      ENV["RAP_VOCAL"] = "sirkel_sag"
      entry = rap_vocal_resolve("sirkel_sag")
      puts JSON.generate(
        slug: entry&.dig("slug"),
        stream: rap_vocal_stream_slug,
        has_path: !!(entry && entry["vocal_path"])
      )
    RUBY
    assert_equal "sirkel_sag", result.fetch("slug")
    assert_equal "sirkel_sag", result.fetch("stream")
    assert result.fetch("has_path"), "catalog should resolve sirkel_sag vocal path"
  end

  def test_rap_vocal_slug_and_atempo_chain
    result = eval_in_engine(<<~RUBY)
      puts JSON.generate(
        slug: rap_vocal_slug("MF DOOM"),
        chain: rap_vocal_atempo_chain(0.92),
        offset: rap_vocal_best_bar_offset("/dev/null", 88, phrases: [{ "start" => 0.0 }, { "start" => 2.0 }])
      )
    RUBY
    assert_equal "mf_doom", result.fetch("slug")
    assert_includes result.fetch("chain"), "atempo="
  end

  def test_flylo_drum_overlay_schedules_dual_bus_events
    result = eval_in_engine(<<~RUBY)
      ENV["FLYLO_DRUM_OVERLAY"] = "1"
      ENV["FLYLO_QUINT_HATS"] = "1"
      ENV["KICKS"] = "1"
      pads = curated_progression_pads(:fourth_third_sixth_second_turn) ||
             [{ name: "Dbmaj9", hz: [58.0, 73.0, 87.0] }, { name: "Cm9", hz: [55.0, 65.0, 82.0] }]
      beat_p = 60.0 / 88.0
      events = dilla_schedule(8, beat_p, pads, chord_bars: 2, feel: :timeless, swing: 57.0)
      puts JSON.generate(
        flylo_kick: events[:flylo_kick]&.length.to_i,
        flylo_hat: events[:flylo_hat]&.length.to_i,
        flylo_quint: events[:flylo_quint]&.length.to_i,
        flylo_perc: events[:flylo_perc]&.length.to_i,
        enabled: flylo_drum_overlay_enabled?
      )
    RUBY
    assert result.fetch("enabled")
    assert_operator result.fetch("flylo_kick"), :>, 0
    assert_operator result.fetch("flylo_hat"), :>, 0
    assert_operator result.fetch("flylo_quint"), :>, 0
    assert_operator result.fetch("flylo_perc"), :>, 0
  end

  def test_stream_iterate_evolve_flylo_drums_returns_notes
    result = eval_in_engine(<<~RUBY)
      ENV["FLYLO_DRUM_OVERLAY"] = "1"
      ENV["DILLA_STREAMING"] = "1"
      ENV["STREAM_ITERATE"] = "1"
      ENV["STREAM_FLYLO_EVERY"] = "1"
      @stream_iterate_count = 2
      notes = stream_iterate_evolve_flylo_drums!
      puts JSON.generate(
        notes: notes,
        gain: ENV["FLYLO_OVERLAY_GAIN"],
        grid: ENV["FLYLO_GRID_BIAS"]
      )
    RUBY
    assert result.fetch("notes").any? { |n| n.start_with?("flylo_gain=") }
    assert result.fetch("gain").to_s.length.positive?
    assert result.fetch("grid").to_s.length.positive?
  end

  def test_stream_iterate_harmony_and_analog_return_notes_when_due
    result = eval_in_engine(<<~RUBY)
      ENV["DILLA_STREAMING"] = "1"
      ENV["STREAM_ITERATE"] = "1"
      ENV["STREAM_HARMONY_EVERY"] = "1"
      ENV["STREAM_ANALOG_EVERY"] = "1"
      @stream_iterate_count = 2
      harm = stream_iterate_evolve_harmony!
      analog = stream_iterate_analog_emulation!
      puts JSON.generate(
        harm: harm,
        analog: analog,
        track: ENV["TRACK"],
        voicing: ENV["VOICING"],
        analog_chain: ENV["ANALOG_CHAIN"]
      )
    RUBY
    assert result.fetch("harm").any? { |n| n.start_with?("voicing=") }
    assert result.fetch("analog").any? { |n| n.start_with?("analog=") }
    assert result.fetch("track").to_s.length.positive?
    assert result.fetch("voicing").to_s.length.positive?
    assert result.fetch("analog_chain").to_s.length.positive?
  end

  def test_dilla_sidechain_style_selects_fast_duck_for_dilla_family
    result = eval_in_engine(<<~RUBY)
      dilla = sidechain_filter_chain({ style_family: :dilla })
      flylo = sidechain_filter_chain({ style_family: :flylo })
      puts JSON.generate(
        dilla_release: dilla.join.include?("release=90"),
        flylo_release: flylo.join.include?("release=14")
      )
    RUBY
    assert result.fetch("dilla_release"), "dilla sidechain should use tight release"
    assert result.fetch("flylo_release"), "flylo sidechain unchanged"
  end

  def test_wrapper_style_mapping_produces_engine_flags
    # The wrapper's execution is guarded, so it loads cleanly in-process and
    # only defines the DillaEntrypoint namespace.
    load WRAPPER unless defined?(DillaEntrypoint)
    args = DillaEntrypoint.engine_args("flylo", "/tmp/out.mp3", 112)
    assert_includes args, "--track=chromatic_mediant_drift"
    assert_includes args, "--sidechain=1"
    assert_equal "112", args.last
    assert_equal "dilla", args[1]

    # Every flag the wrapper emits must be one the engine accepts.
    engine_flags = eval_in_engine("puts JSON.generate(FLAG_ENV.keys)")
    DillaEntrypoint::SETTINGS_FOR_TRACK.each_value do |settings|
      assert_empty settings.keys - engine_flags, "wrapper emits flags the engine doesn't know"
    end
  end

  # Whole-pipeline smoke: synthesizes real audio, so it's opt-in.
  # Run with: DILLA_SMOKE=1 bundle exec ruby -Itest test/test_dilla_lab.rb
  def test_smoke_two_bar_render_produces_playable_audio
    skip "set DILLA_SMOKE=1 to run the render smoke test" unless ENV["DILLA_SMOKE"] == "1"
    skip "ffmpeg/ffprobe not available" unless system("which ffmpeg ffprobe > /dev/null 2>&1")
    Dir.mktmpdir do |dir|
      out = File.join(dir, "smoke.mp3")
      _stdout, err, status = Open3.capture3(
        { "DILLA_SCRATCH_DIR" => File.join(dir, "scratch") },
        RbConfig.ruby, ENGINE, "dilla", out, "2"
      )
      assert status.success?, "2-bar render failed: #{err}"
      assert File.file?(out), "render reported success but wrote no file"
      duration, = Open3.capture3("ffprobe", "-v", "error", "-show_entries", "format=duration",
                                 "-of", "default=noprint_wrappers=1:nokey=1", out)
      assert duration.to_f.positive?, "rendered file has no measurable duration"
    end
  end
end
