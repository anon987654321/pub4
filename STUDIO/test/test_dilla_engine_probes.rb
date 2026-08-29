# frozen_string_literal: true

require_relative "studio_helper"
require "json"
require "open3"
require "rbconfig"
require "timeout"

# Dilla engine (STUDIO/dilla/dilla.rb) defines top-level constants, so probes
# load it in a subprocess — loading here would leak ROOT/OUTPUT_DIR into the
# shared test process. CLI dispatch is guarded by `__FILE__ == $PROGRAM_NAME`.
class TestDilla < Minitest::Test
  ENGINE = File.expand_path("../dilla/dilla.rb", __dir__)

  # A hung probe (coltrane-gem hang — see README) used to pin a
  # dilla_test_probe process near 100% CPU forever with no output and no
  # test failure — a silently-stuck test run. Bounded here: on timeout
  # the child (and its process group, in case it spawned ffmpeg/fluidsynth)
  # gets killed and the test fails loudly instead of hanging the suite.
  # Every probe loads the whole engine in a fresh subprocess, and `rake test`
  # runs these alongside 880-odd other tests, so a fixed 30s budget was tight
  # enough to fire spuriously under load — one run errored here with
  # Timeout::Error while the next passed. 90s still bounds a genuine hang (the
  # coltrane-gem case below) without failing on a busy machine; DILLA_PROBE_TIMEOUT
  # overrides it for slower hosts.
  PROBE_TIMEOUT = Integer(ENV.fetch("DILLA_PROBE_TIMEOUT", "90"))

  # There is no state restoration here, deliberately. Its absence is the fix,
  # not a regression, and the reason is worth keeping because a restoring version
  # looks strictly safer than having nothing.
  #
  # Loading the engine writes dilla's session and learnings JSON, and those are
  # tracked files in a tree this suite does not own. Two separate hooks restored
  # them: Studio.restore_engine_state! in test/studio_helper.rb, and a Minitest.after_run
  # block here. Two hooks, one file, and -- this is the part that made it a bug --
  # SNAPSHOTS TAKEN AT DIFFERENT MOMENTS.
  #
  #   test/studio_helper.rb        binreads project/**/*.json when the helper loads.
  #   test/dilla/helper.rb  then requires the engine, WHICH WRITES session.json.
  #   this file             binread the same paths after that, at its own load.
  #
  # So the helper held the pristine bytes and this file held the already-dirtied
  # ones. Both fired at exit, and whichever ran last decided the outcome -- with
  # this one last, the "restore" put the engine's load-time write back and undid
  # the helper's work. `M STUDIO/dilla/project/session.json` after a clean suite
  # run is that, and it is exactly the tree-dirtying the block was added to stop.
  #
  # The second cost was a flaky test. test_dilla_frozen_... asserted the file's
  # MTIME, and a restore that writes byte-identical content still moves an mtime,
  # so a hook doing nothing meaningful could fail a test about the engine. That
  # test now asserts content, which is what its own contract is about.
  #
  # One hook, snapshotting earliest, covering a superset of these three paths:
  # test/studio_helper.rb's glob is dilla/project/**/*.json. Nothing is lost by deleting
  # this, and the earlier snapshot is the correct one.

  # `env:` is injected before the engine loads, which is the only point at which
  # it can matter: the engine reads most switches into constants and memoizes
  # pools at load, so setting ENV inside `script` is too late and silently reads
  # back the default. A test that flips a switch between two calls in one process
  # gets the first pool twice.
  # Retried once on timeout, because a timeout is not a hang.
  #
  # The bound exists for a real failure — the coltrane-gem hang pinned a probe
  # near 100% CPU forever with no output and no test failure. But every probe
  # loads the whole engine in a fresh subprocess and some of them render audio,
  # and the budget has now been too tight twice for the same reason: 30s fired
  # spuriously, was raised to 90s, and 90s fires spuriously on a machine with
  # other sessions on it. The two-bar smoke render takes 21s alone and exceeds
  # 90s under contention.
  #
  # Raising it again trades away the thing it is for. A hang does not finish on
  # the second attempt either, so one retry separates the two: a genuine hang
  # costs twice the budget and still fails, and a load spike costs one wasted
  # probe and passes. This is the same conclusion RAILS/gates dns_zones reached
  # about a dropped UDP packet — a timeout is not an absent record.
  def eval_in_engine(script, timeout: PROBE_TIMEOUT, env: {})
    attempt = 0
    begin
      attempt += 1
      run_engine_probe(script, timeout: timeout, env: env)
    rescue Timeout::Error
      retry if attempt < 2

      flunk "engine probe timed out after #{timeout}s twice — a load spike does not " \
            "survive a retry, so this is the hang the bound is for (see README, coltrane-gem)"
    end
  end

  def run_engine_probe(script, timeout:, env:)
    preamble = env.map { |k, v| "ENV[#{k.to_s.dump}] = #{v.to_s.dump}" }.join("\n")
    probe = <<~RUBY
      $PROGRAM_NAME = "dilla_test_probe"
      #{preamble}
      load #{ENGINE.dump}
      require "json"
      #{script}
    RUBY
    out = nil
    err = nil
    status = nil
    Open3.popen3(RbConfig.ruby, "-e", probe, pgroup: true) do |stdin, stdout, stderr, wait_thr|
      stdin.close
      begin
        Timeout.timeout(timeout) do
          out = stdout.read
          err = stderr.read
          status = wait_thr.value
        end
      rescue Timeout::Error
        # Kill the group before re-raising: the retry must not race a probe that
        # is still holding ffmpeg or fluidsynth open.
        pgid = Process.getpgid(wait_thr.pid) rescue wait_thr.pid
        Process.kill("-KILL", pgid) rescue nil
        raise
      end
    end
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

  def test_commands_list_is_dispatch_only_no_aliases
    result = eval_in_engine(<<~RUBY)
      puts JSON.generate(
        commands: COMMANDS,
        dispatch_keys: DISPATCH.keys,
        has_aliases_const: defined?(COMMAND_ALIASES)
      )
    RUBY
    assert_equal result.fetch("dispatch_keys").sort, result.fetch("commands")
    refute result.fetch("has_aliases_const"), "COMMAND_ALIASES should be gone"
    assert_includes result.fetch("dispatch_keys"), "dilla"
    assert_includes result.fetch("dispatch_keys"), "demo-all"
    refute_includes result.fetch("dispatch_keys"), "comfort"
    refute_includes result.fetch("dispatch_keys"), "warp"
    refute_includes result.fetch("dispatch_keys"), "camel"
  end

  def test_stream_defaults_keep_style_dna_not_creative_max
    result = eval_in_engine(<<~RUBY)
      %w[STREAM_CREATIVE STREAM_PUNCH STREAM_COMFORT DILLA_COMFORT LA_BEAT_PROGRESSION
         VINYL SELF_SAMPLE CONV_REVERB STREAM_LUFS PAD_VOL].each { |k| ENV.delete(k) }
      ENV["SPEAK"] = "0"
      apply_stream_listenability_defaults!
      puts JSON.generate(
        comfort: comfort_mode?,
        creative: stream_creative_mode?,
        la_beat: ENV["LA_BEAT_PROGRESSION"],
        vinyl: ENV["VINYL"],
        self_sample: ENV["SELF_SAMPLE"],
        conv: ENV["CONV_REVERB"],
        lufs: ENV["STREAM_LUFS"],
        pad_vol: ENV["PAD_VOL"],
        dna_pad_vol: DILLA_STYLE_DEFAULTS["PAD_VOL"],
        crossfade: ENV["STREAM_CROSSFADE"],
        drum_rotate: ENV["STREAM_DRUM_ROTATE"],
        choir: ENV["CHOIR_VOX"]
      )
    RUBY
    refute result.fetch("comfort")
    refute result.fetch("creative")
    assert_equal "0", result.fetch("la_beat"), "style DNA keeps curated progressions"
    # DILLA_STYLE_DEFAULTS' canonical DNA carries VINYL=1 (this path runs
    # through apply_dilla_style!(force: true) via apply_stream_listenability_defaults!).
    assert_equal "1", result.fetch("vinyl")
    assert_equal "0", result.fetch("self_sample")
    assert_equal "0", result.fetch("conv")
    assert_equal "-16.5", result.fetch("lufs")
    # Tracks DILLA_STYLE_DEFAULTS["PAD_VOL"], raised 62 -> 72 -> 86 (e3a046f22,
    # Store P over lush neo-soul pads) so Rhodes/Prophet read over the kit. The
    # assertion here is that the stream path applies the DNA, not that the DNA
    # holds any one number.
    assert_equal result.fetch("dna_pad_vol"), result.fetch("pad_vol")
    assert_equal "0.12", result.fetch("crossfade")
    assert_equal "1", result.fetch("drum_rotate")
    # VOCAL_CARVE is not asserted here. Two defaults tables set it to "1"
    # tables and read by exactly one method, DillaMaster.vocal_carve_placeholder?,
    # which nothing called -- so this assertion only ever proved the string had
    # been written into ENV, never that a single pad was carved under a vocal.
    # Flag and reader are both gone; if the carve is wanted it needs building,
    # and this line would not have noticed either way.
    assert_equal "0", result.fetch("choir")
  end

  def test_stream_creative_mode_opt_in_forces_wild_layer
    result = eval_in_engine(<<~RUBY)
      ENV["STREAM_CREATIVE"] = "1"
      ENV["SPEAK"] = "0"
      apply_stream_listenability_defaults!
      puts JSON.generate(
        creative: stream_creative_mode?,
        la_beat: ENV["LA_BEAT_PROGRESSION"],
        vinyl: ENV["VINYL"],
        lufs: ENV["STREAM_LUFS"]
      )
    RUBY
    assert result.fetch("creative")
    assert_equal "1", result.fetch("la_beat")
    assert_equal "1", result.fetch("vinyl")
    assert_equal "-14.5", result.fetch("lufs")
  end

  def test_sh_timeout_helper_and_soft_choir_helpers_exist
    result = eval_in_engine(<<~RUBY)
      puts JSON.generate(
        timeout: sh_timeout_sec,
        has_system_timeout: respond_to?(:system_with_timeout, true),
        choir_methods: respond_to?(:choir_vox_enabled?, true) &&
                       respond_to?(:choir_chord_tone_events, true),
        soft_max_keys: STREAM_CREATIVE_MAX.keys.sort,
        style_safe_keys: STREAM_STYLE_SAFE.keys.sort
      )
    RUBY
    assert_operator result.fetch("timeout"), :>=, 30
    assert result.fetch("has_system_timeout")
    assert result.fetch("choir_methods")
    refute_includes result.fetch("soft_max_keys"), "SPEAK"
    assert_includes result.fetch("style_safe_keys"), "STREAM_DRUM_ROTATE"
  end

  def test_single_engine_mode_empty_render_mode_is_dilla
    result = eval_in_engine(<<~RUBY)
      ENV.delete("RENDER_MODE")
      normalize_render_mode!
      puts JSON.generate(mode: ENV["RENDER_MODE"], dilla: dilla_style?)
    RUBY
    assert_equal "dilla", result.fetch("mode")
    assert result.fetch("dilla")
  end

  def test_choir_chord_tones_are_thinned_mid_upper
    result = eval_in_engine(<<~RUBY)
      pads = [
        [0.0, 0.9, { name: "Fm9", hz: [87.31, 174.61, 207.65, 261.63, 311.13] }, 3.8],
        [4.0, 0.85, { name: "Cm7", hz: [130.81, 155.56, 196.0] }, 3.8],
      ]
      thinned = choir_chord_tone_events(pads)
      puts JSON.generate(
        n: thinned.length,
        tones0: thinned[0][2][:hz].length,
        tones1: thinned[1][2][:hz].length,
        mid_upper0: thinned[0][2][:hz].min > 100.0,
        name_tag: thinned[0][2][:name].to_s.include?("choir")
      )
    RUBY
    assert_equal 2, result.fetch("n")
    assert_operator result.fetch("tones0"), :<=, 3
    assert_operator result.fetch("tones1"), :<=, 3
    assert result.fetch("mid_upper0")
    assert result.fetch("name_tag")
  end

  def test_neosoul_pocket_has_expanded_phrase_variety
    result = eval_in_engine(<<~RUBY)
      ENV["POCKET_SET"] = "neo_soul"
      kicks = DillaGroove.kick_phrases
      sparse = DillaGroove.kick_sparse_phrases
      ghosts = DillaGroove.snare_ghost_phrases
      hats = DillaGroove.hat_phrases
      dense = kicks.any? { |p| p.length > 4 }
      puts JSON.generate(
        kick_n: kicks.length,
        sparse_n: sparse.length,
        ghost_n: ghosts.length,
        hat_n: hats.length,
        any_dense_kick: dense,
        has_empty_sparse: sparse.any?(&:empty?),
        max_hat: hats.map(&:length).max
      )
    RUBY
    assert_operator result.fetch("kick_n"), :>=, 12
    assert_operator result.fetch("sparse_n"), :>=, 6
    assert_operator result.fetch("ghost_n"), :>=, 8
    assert_operator result.fetch("hat_n"), :>=, 8
    refute result.fetch("any_dense_kick"), "neo-soul kicks must stay sparse (≤4 hits)"
    assert result.fetch("has_empty_sparse"), "breathing bars should include empty kick phrases"
    assert_operator result.fetch("max_hat"), :<=, 8, "neo-soul hats must not fill the 16th grid"
  end

# DILLA_PROGRESSIONS_ONLY narrows to Dilla-produced progressions, and
# ModalFamily.widen (2026-07-30) then widens outward from that core to every
# catalogue progression sharing the locked key and mode — 5 tracks became 203.
#
# This asserted the narrow pool exactly, so it went red when the widening
# landed. What matters is not the count: it is that the Dilla-produced tracks
# still lead the rotation, that everything admitted is in the same modal
# family, and that MODAL_ROTATION=0 restores the old pool exactly.
  def test_stream_rotation_leads_with_dilla_produced_then_widens_by_mode
    # Two engine invocations rather than one with ENV flipped between calls:
    # the pools memoize, so a second read in the same process returns the first.
    narrow_result = eval_in_engine(<<~INNER, env: { "MODAL_ROTATION" => "0" })
      puts JSON.generate(
        order: stream_track_order.map(&:to_s),
        produced: DILLA_PRODUCED_TRACKS.map(&:to_s),
        rotation: DillaLofiMachine::STREAM_ROTATION.map(&:to_s)
      )
    INNER
    wide_result = eval_in_engine(<<~INNER)
      puts JSON.generate(order: stream_track_order.map(&:to_s))
    INNER

    narrow = narrow_result.fetch("order")
    wide = wide_result.fetch("order")
    produced = narrow_result.fetch("produced")
    expected_narrow = narrow_result.fetch("rotation").select { |t| produced.include?(t) }

    assert_equal expected_narrow, narrow, "MODAL_ROTATION=0 restores the Dilla-produced pool exactly"
    assert_equal "pedal_e_descent", wide.first, "the core still leads the widened rotation"
    assert_operator wide.length, :>, narrow.length, "widening admits the rest of the modal family"
    # Not "the core is contiguous at the head" — it is not. ModalFamily.widen
    # returns core-first, but stream_track_order reorders afterwards, so only
    # pedal_e_descent reliably leads. The invariant that actually matters is that
    # widening never drops a Dilla-produced track: it adds to the core, it does
    # not replace it.
    assert_empty narrow - wide, "widening must not drop any Dilla-produced track"
  end

  def test_stream_rotation_without_the_filter_is_the_full_curated_pool
    result = eval_in_engine(<<~RUBY)
      ENV["DILLA_PROGRESSIONS_ONLY"] = "0"
      order = stream_track_order.map(&:to_s)
      puts JSON.generate(order_n: order.length, head: order.first(3), has_untitled: order.include?("d_add9_soul_arc"))
    RUBY
    assert_operator result.fetch("order_n"), :>=, 8
    assert_equal "pedal_e_descent", result.fetch("head").first
    assert result.fetch("has_untitled"), "the unfiltered pool keeps the non-Dilla curated tracks"
  end

  def test_stream_rotates_drums
    result = eval_in_engine(<<~RUBY)
      stream_rotate_drums!(0)
      d0 = ENV["DRUM_PRESET"]
      stream_rotate_drums!(1)
      d1 = ENV["DRUM_PRESET"]
      puts JSON.generate(drum0: d0, drum1: d1, drums_differ: d0 != d1)
    RUBY
    assert result.fetch("drums_differ"), "drum rotation should change DRUM_PRESET"
  end

  def test_theory_runtime_refines_progression_without_dropping_chords
    result = eval_in_engine(<<~RUBY)
      chords = [
        { name: "Fm9", hz: [174.61, 207.65, 261.63, 311.13] },
        { name: "Bbm9", hz: [233.08, 277.18, 349.23, 415.30] },
        { name: "Ebmaj9", hz: [155.56, 196.00, 233.08, 311.13] },
      ]
      ENV["THEORY_RUNTIME"] = "1"
      ENV["THEORY_DILLA"] = "1"
      ENV["THEORY_BACH"] = "1"
      refined = DillaTheoryRuntime.refine_progression!(chords, cfg: { track: "neo_soul" })
      puts JSON.generate(
        n: refined.length,
        names: refined.map { |c| c[:name] },
        has_hz: refined.all? { |c| Array(c[:hz]).length >= 2 }
      )
    RUBY
    assert_equal 3, result.fetch("n")
    assert_equal %w[Fm9 Bbm9 Ebmaj9], result.fetch("names")
    assert result.fetch("has_hz")
  end

  def test_apply_voicing_returns_bounded_playable_chords_for_every_style
    result = eval_in_engine(<<~RUBY)
      hz = [174.61, 207.65, 261.63, 311.13] # Fm7
      bad = %i[quartal drop2 drop3 spread cluster].filter_map do |style|
        voiced = DillaHarmony.apply_voicing(hz, style:)
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
      cfg = { bpm: 94, swing: 57, track: :warm_minor_vamp }
      patch = { id: :prophet_5_pad, arp_styles: %i[updown pingpong] }
      # NO_ARP defaults on from 2026-08-01, and it outranks PAD_ARP_MODE by
      # design. This test is about the arp routing itself, which is still there
      # and still correct, so it opts back in rather than asserting the default.
      ENV["NO_ARP"] = "0"
      ENV["PAD_ARP_MODE"] = "wash"
      ENV["LEAD_ARP"] = "1"
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
    assert result.fetch("lead_enabled"), "LEAD_ARP=1 + wash pad arp enables lead"
    # PAD_ARP_MODE=wash → LEAD_ARP_MODE soul_wash (LEAD_ARP_PRESETS).
    assert_equal "updown", result.fetch("lead_style").to_s
    assert_equal 2, result.fetch("lead_subdiv"), "wash PAD_ARP_MODE maps to soul_wash lead preset"
  end

  def test_best_defaults_align_with_style_so_one_shot_wires_full_dna
    result = eval_in_engine(<<~RUBY)
      # Simulate clean one-shot path: boot soft BEST then soft STYLE.
      (DILLA_BEST_DEFAULTS.keys | DILLA_STYLE_DEFAULTS.keys | DILLA_DEEP_DEFAULTS.keys |
       %w[TRACK PROGRESSION RENDER_MODE]).each { |k| ENV.delete(k) }
      apply_best_defaults!
      apply_dilla_style!(force: false)
      # SONITEX/SONITEX_PRESET/ANALOG_CHAIN/VINYL are a documented, intentional
      # exception (see DILLA_BEST_DEFAULTS' own comment on those keys): BEST
      # keeps the safer donuts_soul/broadcast for callers that never force
      # style, while STYLE force-applies donuts_warm/vinyl_hot/VINYL=1.
      known_exceptions = %w[SONITEX SONITEX_PRESET ANALOG_CHAIN VINYL]
      conflicts = DILLA_BEST_DEFAULTS.reject { |k, _| known_exceptions.include?(k) }.select { |k, v|
        DILLA_STYLE_DEFAULTS.key?(k) && v.to_s != DILLA_STYLE_DEFAULTS[k].to_s
      }
      puts JSON.generate(
        master: ENV["MASTER_HEURISTICS"],
        pad_voice: ENV["PAD_VOICE"],
        pad_arp: ENV["PAD_ARP_MODE"],
        analog: ENV["ANALOG_CHAIN"],
        kick_gain: ENV["KICK_GAIN"],
        composition: ENV["COMPOSITION"],
        groove_engine: ENV["GROOVE_ENGINE"],
        pocket_dna: ENV["POCKET_DNA"],
        harmony_lead: ENV["HARMONY_LEAD"],
        lead_arp: ENV["LEAD_ARP"],
        track: ENV["TRACK"],
        phrase_drift: ENV["PHRASE_DRIFT"],
        swing_jitter: ENV["SWING_JITTER"],
        fm_drums: ENV["FM_DRUMS"],
        fm_on: fm_drums_enabled?,
        kick_double: ENV["KICK_DOUBLE"],
        kick_drop: ENV["KICK_DROP"],
        snare_prehit: ENV["SNARE_PREHIT_GHOST"],
        phone: ENV["PHONE_PREVIEW_GATE"],
        choir: ENV["CHOIR_VOX"],
        theory: ENV["THEORY_RUNTIME"],
        dfam: DfamEngine.enabled?,
        spectral: DillaSpectral.enabled?,
        master_on: DillaMaster.enabled?,
        harmony_on: harmony_lead_enabled?,
        composition_on: composition_enabled?,
        conflicts: conflicts
      )
    RUBY
    assert_equal "1", result.fetch("master")
    assert_equal "moog", result.fetch("pad_voice")
    assert_equal "held", result.fetch("pad_arp")
    # DILLA_STYLE_DEFAULTS carries vinyl_hot (see its own comment on why
    # DILLA_BEST_DEFAULTS keeps the safer broadcast for other callers) --
    # it wins here too since apply_dilla_style! fill/forces ANALOG_CHAIN.
    assert_equal "vinyl_hot", result.fetch("analog")
    # 0.68 is the STREAM-only quiet-kit-bus value (STREAM_EXTRA_DEFAULTS);
    # the one-shot best+style path this test exercises agrees on 0.88.
    assert_equal "0.88", result.fetch("kick_gain")
    assert_equal "1", result.fetch("composition")
    assert_equal "1", result.fetch("groove_engine")
    assert_equal "1", result.fetch("pocket_dna")
    # The lead layers are on. "drop the leads" (cd8e6850f, 058ff18f3) turned all
    # four off and 0a77242dd turned three back on, because the signature sound
    # layers an arp locked to the progression scale over the counter-line.
    assert_equal "1", result.fetch("harmony_lead")
    assert_equal "1", result.fetch("lead_arp")
    assert_equal "slum_village_intro_documented", result.fetch("track")
    assert_equal "1", result.fetch("phrase_drift")
    assert_equal "1", result.fetch("swing_jitter")
    # The FM kit is the default, and this assertion used to say the opposite.
    #
    # 6e5eed932 added both `"FM_DRUMS" => "0"` to DILLA_BEST_DEFAULTS and the
    # "soul pocket uses sample kit" expectation here. That commit was a
    # styles-collapse refactor whose message says nothing about drums; it
    # silently reverted 1e74b12fd, which had made the FM kit the
    # full-replacement default as a measured user choice (harshness -19.66 dB
    # against the analog kit's -17.68 dB). 6d6f922db restored the "1" on
    # 2026-07-28 and documented why at DILLA_BEST_DEFAULTS' FM_DRUMS key.
    #
    # The engine change is the intended one, so the test follows it. Pinning
    # "0" here left `rake test` red while encoding the rejected choice.
    assert_equal "1", result.fetch("fm_drums"), "FM kit is the measured default (6d6f922db)"
    assert result.fetch("fm_on"), "fm_drums_enabled? agrees with the FM_DRUMS default"
    assert_equal "1", result.fetch("kick_double")
    assert_equal "1", result.fetch("kick_drop")
    assert_equal "1", result.fetch("snare_prehit")
    assert_equal "0", result.fetch("phone"), "style DNA keeps phone preview off unless forced"
    # CHOIR_VOX defaults off since 2026-08-01 — the demo and the engine are
    # instrumental by default, and choir is a vocal.
    assert_equal "0", result.fetch("choir")
    assert_equal "1", result.fetch("theory")
    assert result.fetch("dfam")
    assert result.fetch("spectral")
    assert result.fetch("master_on")
    assert result.fetch("harmony_on"), "harmony_lead_enabled? agrees with HARMONY_LEAD=1"
    assert result.fetch("composition_on")
    assert_empty result.fetch("conflicts"), "BEST must not soft-block STYLE DNA"
  end

  def test_ghost_and_open_events_receive_pocket_timing
    result = eval_in_engine(<<~RUBY)
      # DRUMS=1 because drums default off -- drum_policy names this as the way
      # back. Without it dilla_schedule returns no kick, and a test about where
      # the ghost hits land measures whether drums are on instead.
      ENV["DRUMS"] = "1"
      ENV["DILLA_RAW"] = "1"
      ENV["GROOVE_ENGINE"] = "1"
      ENV["POCKET_DNA"] = "1"
      ENV["SWING_JITTER"] = "1"
      ENV["PHRASE_DRIFT"] = "1"
      ENV["DILLA_RENDER_SEED"] = "42"
      cfg = { track: :pedal_e_descent, bpm: 92.0, swing: 56.0, feel: :dilla_slight,
              timing: {}, chord_bars: 4, phrase_bars: 8, quintuplet: false,
              progression: :pedal_e_descent, style_family: :dilla }
      pads = [{ name: "Cm7", hz: [130.81, 155.56, 196.0, 233.08] },
              { name: "Fm7", hz: [174.61, 207.65, 261.63, 311.13] }]
      beat_p = 60.0 / 92.0
      events = dilla_schedule(8, beat_p, pads, chord_bars: 4, phrase_bars: 8,
                              swing: 56.0, feel: :dilla_slight, timing: {},
                              quintuplet: false, chord_phases: [])
      ghosts = Array(events[:ghost])
      opens = Array(events[:open])
      # Quantized step times without pocket place would be exact multiples;
      # pocket timing should introduce non-zero offsets on at least some hits.
      ghost_offs = ghosts.map { |t, *_| ((t / (beat_p / 4.0)) % 1.0) }
      puts JSON.generate(
        ghost_n: ghosts.length,
        open_n: opens.length,
        ghost_fractional: ghost_offs.count { |f| f > 0.001 && f < 0.999 },
        kick_n: Array(events[:kick]).length,
        snare_n: Array(events[:snare]).length
      )
    RUBY
    assert_operator result.fetch("kick_n"), :>, 0
    assert_operator result.fetch("snare_n"), :>, 0
    assert_operator result.fetch("ghost_n"), :>, 0
    assert_operator result.fetch("ghost_fractional"), :>, 0,
                   "ghost events should receive pocket micro-timing, not sit on the dead grid"
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
      grid = BUILTIN_LEARNED_ENGINE.dig("drum_grids", "quartal_west_coast")
      kicks = grid["wonky_kicks"]
      snares = grid["wonky_snares"]
      puts JSON.generate(
        bpm: grid&.dig("bpm"),
        builtin: grid["wonky_kicks"] == POLY_TEMPORAL_DRUM_GRID["wonky_kicks"],
        kicks: kicks,
        snares: snares,
        kick_count: kicks&.length,
        syncopated: kicks&.any? { |s| s.odd? }
      )
    RUBY
    assert_equal 86, result.fetch("bpm")
    assert result.fetch("builtin"), "Camel grid should be baked into dilla.rb"
    assert_operator result.fetch("kick_count"), :>=, 2
    assert_operator result.fetch("kick_count"), :<=, 4
    assert_includes result.fetch("kicks"), 0
    assert_includes result.fetch("snares"), 4
    assert_includes result.fetch("snares"), 12
  end

  def test_dilla_style_applies_defaults_and_grid
    result = eval_in_engine(<<~RUBY)
      ENV["DILLA_STREAMING"] = "1"
      remove_instance_variable(:@learned_engine_cache) if instance_variable_defined?(:@learned_engine_cache)
      apply_dilla_style!(force: true)
      grid = wonky_drum_grid_for(ENV["TRACK"])
      puts JSON.generate(
        mode: ENV["RENDER_MODE"],
        track: ENV["TRACK"],
        bpm: ENV["BPM"],
        kicks: ENV["KICKS"],
        rap: ENV["RAP_VOCAL"],
        la_beat: la_beat_progression_enabled?,
        form: ENV["FORM"],
        groove: ENV["GROOVE_DNA"],
        stream_track: ENV["STREAM_TRACK"],
        pocket_drums: dilla_pocket_drums_enabled?,
        kicks_enabled: kicks_enabled?,
        grid_bpm: grid&.dig("bpm"),
        wonky_kicks: grid&.dig("wonky_kicks"),
        wonky_snares: grid&.dig("wonky_snares"),
        drums_only: wonky_drums_only?,
        progression: load_learned_engine.dig("progressions", ENV["TRACK"])&.length
      )
    RUBY
    assert_equal "dilla", result.fetch("mode")
    assert_equal "slum_village_intro_documented", result.fetch("track")
    # DILLA_STYLE_DEFAULTS deliberately does NOT force BPM (see its own
    # comment): forcing "92" here used to silently clobber every other
    # track's own tuned tempo. resolve_bpm falls back to the track preset
    # itself (still 92 for pedal_e_descent) when ENV["BPM"] is unset.
    assert_nil result.fetch("bpm")
    assert_includes %w[0 1], result.fetch("kicks")
    # gunnhild is the only vocal source (2026-07-27); this asserted jonas_v,
    # which the style defaults stopped selecting when that decision landed.
    # Was "gunnhild". The engine is instrumental by default from 2026-08-01;
    # RAP_VOCAL=<slug> opts back in.
    assert_equal "0", result.fetch("rap"), "style default is instrumental; RAP_VOCAL names a voice to opt in"
    assert_nil result.fetch("stream_track")
    refute result.fetch("la_beat"), "curated progressions only (no random planing)"
    assert_equal "camel_32", result.fetch("form")
    assert_equal "donuts", result.fetch("groove")
    # Pocket DNA + overlay kit are both on under dilla style defaults.
    assert result.fetch("pocket_drums") || !result.fetch("kicks_enabled")
    # FlyLo overlay grid is optional per track; when present, pocket 2&4 snares.
    return unless result.fetch("grid_bpm")

    assert_equal 92, result.fetch("grid_bpm")
    assert_includes result.fetch("wonky_kicks"), 0
    assert_includes result.fetch("wonky_snares"), 4
    assert_includes result.fetch("wonky_snares"), 12
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
      ENV["WONKY_DRUM_OVERLAY"] = "1"
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
        wonky_kick: events[:wonky_kick]&.length || 0
      )
    RUBY
    # 8, not 12. resolve_chord_bars doubles every preset's chord_bars on the
    # "slower deeper chords always" direction of 2026-08-09, so a progression
    # generated across the same bar count holds each chord twice as long and
    # needs about half as many. Measured 9 here where it was 14.
    #
    # The number was tracking harmonic rhythm rather than the property this
    # test is named for -- the four assertions below (variety of names, variety
    # of lengths, distinct pad voicings, distinct chord indices) are what makes
    # a progression "long and varied", and none of them moved.
    assert_operator result.fetch("chord_count"), :>=, 8
    assert_operator result.fetch("unique_names"), :>=, 3
    assert_operator result.fetch("lens_variety"), :>=, 2
    assert_operator result.fetch("pad_unique"), :>=, 3
    assert_operator result.fetch("index_unique"), :>=, 4
    assert_operator result.fetch("wonky_kick"), :>, 0
  end

  def test_dilla_neosoul_aydin_bach_progressions_resolve
    %i[maj7_minor_cycle neo_soul electronium_loop modal_quartal_ladder minor_two_five_chain
       circle_fifths_descent walking_bass_descent].each do |track|
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
      ENV["TRACK"] = "warm_minor_vamp"
      ENV["DILLA_RAW"] = "1"
      pads = dilla_progression(:warm_minor_vamp)
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
      apply_track_soul_profile!(:warm_minor_vamp)
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
    # MORPH_LEAD_ARP_CYCLE's soul_wash preset style is :updown (see its own table).
    assert_equal "updown", result.fetch("lead_style").to_s
    assert_equal 2, result.fetch("lead_subdiv")
    assert_equal "erykah", result.fetch("track_voice")
    assert_equal "erykah_dust", result.fetch("track_arp")
  end

  # A hand-cut loop only reaches a render when some TRACK name resolves to it:
  # sample_loop_entry looks the track up in TRACK_SAMPLE_LOOPS, so a loop with
  # no matching preset (or alias to one) is selectable only by typing
  # TRACK=<slug> by hand, and never appears in the medley or the rotation.
  # Three of the four measured loops were in that state. Nothing errors when it
  # happens, which is why it needs a test rather than a comment.
  def test_every_hand_cut_sample_loop_is_reachable_as_a_track_preset
    result = eval_in_engine(<<~RUBY)
      presets = TRACK_PRESETS.keys.map(&:to_s)
      # The MERGED rack, not just the hand-cut table: a chopped loop is a sample
      # loop in every sense that matters, and the eight Sheger chops were
      # unreachable in exactly the same way the hand-cut ones were.
      loops = TRACK_SAMPLE_LOOPS.keys.map(&:to_s)
      aliases = TRACK_SAMPLE_LOOP_ALIASES.transform_keys(&:to_s).transform_values(&:to_s)
      excluded = SAMPLE_LOOPS_OUT_OF_ROTATION.map(&:to_s)
      unreachable = (loops - excluded).reject do |slug|
        presets.include?(slug) || aliases.any? { |a, t| t == slug && presets.include?(a) }
      end
      puts JSON.generate(builtin_count: TRACK_SAMPLE_LOOPS_BUILTIN.length, loops: loops, unreachable: unreachable,
                         missing_files: TRACK_SAMPLE_LOOPS.reject { |_, v| File.file?(v[:path]) }.keys)
    RUBY
    # As above: the rack is the builtins until the rebuilt crate registers its
    # chops, and this test's real content is the two assertions below it —
    # a loop with no preset never renders, and an entry pointing at a missing
    # file renders silently with no bed. Those hold at any crate size.
    assert_operator result.fetch("loops").length, :>=, result.fetch("builtin_count")
    assert_empty result.fetch("unreachable"),
                 "hand-cut loops with no preset never render: #{result.fetch('unreachable').inspect}"
    # A ratchet rather than assert_empty, because these four are a known and
    # deliberate state rather than a defect. 74d9e4c1b cleared the crate on the
    # operator's call — 133 renders and 498 samples — and it is being rebuilt
    # from source with yt-dlp and demucs. Their entries stay: the hp and sub_db
    # on each was measured per loop, and deleting the table to satisfy a test
    # would throw away tuning that the files coming back will need.
    #
    # assert_empty here failed the suite for the state the operator asked for.
    # A skip would go quiet and stay quiet. This fails on a fifth, and tightens
    # on its own as the rebuild lands each file.
    awaiting_rebuild = %w[kembara_rindu lo_borges rauingar arat_swost_wolet]
    fileless = result.fetch("missing_files")
    assert_empty fileless - awaiting_rebuild,
                 "a loop entry pointing at a file that is not there renders silently without a bed: " \
                 "#{(fileless - awaiting_rebuild).inspect}"
    assert_operator fileless.length, :<=, awaiting_rebuild.length,
                    "more fileless loops than the crate rebuild accounts for"
  end

  # GENRE names a bundle; it does not seize the controls. Every value in it is
  # soft-filled, so anything the operator pinned survives — a bundle that
  # overrode a deliberate choice would be worse than no bundle. And an unknown
  # genre aborts rather than rendering the default quietly, which is the failure
  # this tree keeps producing: you ask for something, get something else, and
  # nothing says so.
  def test_genre_bundles_fill_without_overriding_and_reject_unknown_names
    result = eval_in_engine(<<~RUBY)
      knobs = %w[POCKET_SET SONITEX SONITEX_PRESET ANALOG_CHAIN VOICING GENRE_HARMONY]
      resolved = GENRE_DEFAULTS.keys.to_h do |g|
        knobs.each { |k| ENV.delete(k) }
        ENV["GENRE"] = g.to_s
        apply_genre!
        [g.to_s, knobs.to_h { |k| [k, ENV[k]] }.compact]
      end
      knobs.each { |k| ENV.delete(k) }
      ENV["VOICING"] = "quartal"
      ENV["GENRE"] = "soul"
      apply_genre!
      pinned = ENV["VOICING"]
      knobs.each { |k| ENV.delete(k) }
      ENV.delete("GENRE")
      puts JSON.generate(resolved: resolved, pinned: pinned,
                         soul_would_set: GENRE_DEFAULTS[:soul]["VOICING"])
    RUBY
    resolved = result.fetch("resolved")
    assert_operator resolved.length, :>=, 5
    assert resolved.key?("techno") && resolved.key?("jazz") && resolved.key?("soul"),
           "the axis exists so techno, jazz and soul are reachable by name"
    assert_equal "1", resolved.dig("techno", "GENRE_HARMONY"),
                 "GENRE=techno must turn the harmonic path on, or the axis colours without connecting anything"
    assert resolved.values.map { |v| v["SONITEX"] }.uniq.length >= 4,
           "bundles that resolve to the same colour are not an axis"
    assert_equal "quartal", result.fetch("pinned"),
                 "a pinned knob must beat the bundle (soul would have set #{result.fetch('soul_would_set')})"
  end

  # Genre is meant to be a parameter, not a fork: dilla leans Detroit hiphop but
  # techno, soul and jazz are supposed to blend rather than live in separate
  # programs. The measurable form of that is whether a renderer can reach the
  # shared spine at all -- the progression, the sampled bed, the groove engine.
  #
  # This does not demand that every renderer use all three. It pins the two
  # facts that matter and that regressed silently before: render_dilla reaches
  # all of it, and the techno renderer can reach harmony, which it could not
  # until TECHNO_HARMONY existed. A future render_<genre> that reaches none of
  # them is the thing this is here to make loud.
  def test_genre_renderers_can_reach_the_shared_spine
    result = eval_in_engine(<<~RUBY)
      src = engine_source
      # Slice to the next COLUMN-ZERO def, not to the next "\\nend\\n": every
      # method here has nested blocks, so the first end belongs to one of them
      # and the body comes back truncated. That is how the first version of
      # this test reported render_dilla as not reaching the sampled bed.
      body = ->(m) {
        i = src.index("\\ndef " + m)
        next "" unless i

        src[i, (src.index("\\ndef ", i + 1) || src.length) - i]
      }
      spine = ->(b) {
        { harmony: !!(b =~ /dilla_progression|techno_harmony_roots|dilla_resolve_config/),
          bed: !!(b =~ /sample_loop_for|build_sample_loop_filter/),
          groove: !!(b =~ /dilla_schedule|gather\\.call|pocket|swing/) }
      }
      puts JSON.generate(
        dilla: spine.call(body.call("render_dilla")),
        techno: spine.call(body.call("render_hate_techno")),
        techno_harmony_is_opt_in: !techno_harmony_enabled?
      )
    RUBY
    d = result.fetch("dilla")
    assert d["harmony"] && d["bed"] && d["groove"],
           "render_dilla is the spine; if it stops reaching one of these the test above it is measuring nothing"
    t = result.fetch("techno")
    assert t["harmony"],
           "the techno renderer must be able to reach the progression, or genre is a fork again"
    assert t["groove"], "the techno renderer builds its own grid; that is still groove"
    assert result.fetch("techno_harmony_is_opt_in"),
           "TECHNO_HARMONY changes the sound of every techno render and must stay opt-in until that is a decision"
  end

  # The same fork, one layer below the notes.
  #
  # Reaching the progression fixed what a genre renderer plays. It did not fix
  # its level, because loudness is set by normalise_master! and that has exactly
  # one call site, at the tail of render_dilla's finaliser. The three renderers
  # that build their own filtergraph each ended in a limiter and stopped, and a
  # limiter caps a peak without setting a loudness.
  #
  # Measured on a 26-track demo before this was wired: the 8 parts that hashed
  # into a techno slot came out at -12.3 LUFS against -18.7 for the other 18.
  # Nothing failed, nothing warned -- the level was never set, and the
  # only symptom was one track in four being twice as loud as its neighbours.
  #
  # render_hiphop is deliberately checked by delegation rather than by grep: its
  # whole body is `render_dilla(destination, bars)`, so it reaches the master the
  # only way that matters. A grep for the call name reports it as a bypass, which
  # is how this test's first version got the answer wrong.
  def test_every_genre_renderer_reaches_the_master_bus
    result = eval_in_engine(<<~RUBY)
      src = engine_source
      body = ->(m) {
        i = src.index("\\ndef " + m)
        next "" unless i

        src[i, (src.index("\\ndef ", i + 1) || src.length) - i]
      }
      # Directly, via the genre helper, or by handing the whole render to a
      # renderer that does one of those.
      masters = ->(b) { !!(b =~ /normalise_master!|normalise_genre_master!|render_dilla\\(/) }
      puts JSON.generate(
        renderers: %w[render_hate_techno render_industrial render_analog render_hiphop]
                     .to_h { |m| [m, masters.call(body.call(m))] },
        # Every family a renderer actually asks for, and whether the mastering
        # table has an entry for it. normalise_genre_master! does
        # `fetch(family, MASTER_LUFS_BY_STYLE[:default])`, so a family with no
        # entry masters at whatever :default happens to say and never mentions
        # it — which is how :analog rendered at -17.0 while looking like it had
        # a target of its own.
        families: src.scan(/(?<!def )normalise_genre_master!\\([^,]+,\\s*:(\\w+)/).flatten.uniq.sort,
        styles: MASTER_LUFS_BY_STYLE.keys.map(&:to_s).sort,
        # The invariant is that techno has its own entry, not what that entry
        # says. This asserted == -17.0 until 2026-08-11, which was the value of
        # :default — so it passed identically whether techno was explicit or
        # falling through, i.e. it could never detect the thing its own message
        # named. It then failed as a regression when the operator asked for -14.
        techno_is_explicit: MASTER_LUFS_BY_STYLE.key?(:techno),
        # The normalise pass re-encodes the file it levels. Hardcoding a bitrate
        # there downgraded every 320k mp3 to 192k as a side effect of a gain.
        reencodes_with_codec_for: !!(body.call("normalise_master!") =~ /codec_for\\(path\\)/)
      )
    RUBY

    result.fetch("renderers").each do |name, reaches|
      assert reaches, "#{name} never sets an integrated loudness, so it will drift " \
                      "against every other renderer the moment they share a playlist"
    end
    # The count was hard-coded at 3 and went stale the moment render_industrial
    # was routed through the spine and started mastering itself — a fourth call
    # site, which is the fix rather than the bug. What the message always meant
    # is asserted directly now: no renderer asks for a family the table has no
    # answer for.
    missing = result.fetch("families") - result.fetch("styles")
    assert_empty missing,
                 "these renderers ask normalise_genre_master! for a family with no entry in " \
                 "MASTER_LUFS_BY_STYLE, so they master at :default and say nothing: #{missing.join(', ')}"
    assert result.fetch("techno_is_explicit"),
           "techno's target must be its own entry in MASTER_LUFS_BY_STYLE rather than " \
           "falling through to :default — the level itself is the operator's to set"
    assert result.fetch("reencodes_with_codec_for"),
           "normalise_master! must re-encode at the renderer's own bitrate, not a hardcoded one"
  end

  # DEVICE_PROGRESSIONS is 140 entries of pure data, and data of this shape
  # fails silently: progression_for rescues ArgumentError and returns nil, so a
  # mistyped symbol does not raise -- it renders a bar of nothing, or drops the
  # chord and shortens the progression, and the log still names the track.
  #
  # The first draft had 21 symbols that did not parse. The cause is worth
  # keeping in a test rather than a comment: plain major is the EMPTY suffix in
  # CHORD_SUFFIXES, not "maj", so "CmajoverG" is invalid where "CoverG" is
  # right. Nothing in the engine would have told anyone.
  def test_device_progressions_all_resolve
    result = eval_in_engine(<<~RUBY)
      bad = []
      DEVICE_PROGRESSIONS.each do |name, chords|
        chords.each do |c|
          r = begin
            DillaProducerDNA.chord_from_symbol(c)
          rescue StandardError
            nil
          end
          bad << "\#{name}:\#{c}" if r.nil? || Array(r[:hz]).empty?
        end
      end
      puts JSON.generate(
        count: DEVICE_PROGRESSIONS.length,
        symbols: DEVICE_PROGRESSIONS.values.sum(&:length),
        bad: bad.first(20),
        # Every one must survive the merge into CHORD_PROGRESSIONS -- a name
        # colliding with an existing entry would be silently overwritten by it.
        unreachable: DEVICE_PROGRESSIONS.keys.reject { |k| CHORD_PROGRESSIONS.key?(k) },
        shortest: DEVICE_PROGRESSIONS.values.map(&:length).min
      )
    RUBY

    assert_equal 150, result.fetch("count")
    assert_empty result.fetch("bad"),
                 "a symbol that does not parse renders as a missing chord, not an error"
    assert_empty result.fetch("unreachable"),
                 "a name that collides with an existing progression is silently overwritten by it"
    assert_operator result.fetch("shortest"), :>=, 2, "a progression needs at least two chords to move"
  end

  # A patch that is defined and never listed in a pool cannot be selected.
  #
  # SYNTH_PATCH_CATALOG is 212 entries and nothing enforces that any of them is
  # reachable, so an addition is one edit away from being decoration. That is
  # not hypothetical: role :bass holds exactly one patch, minimoog_bass, whose
  # id appears nowhere else in the file -- no pool, no preset, no selector. Bass
  # is synthesised through render_harmonic_wav instead, so the whole role is
  # dead weight and has been for as long as it has existed.
  #
  # This pins the gear patches added on 2026-08-09 for J Dilla and Flying Lotus
  # (Voyager, MicroKORG, Access Virus, Motif-Rack) rather than the whole
  # catalogue, because the catalogue is not clean and a test that fails on
  # arrival teaches nobody anything. The :bass hole is recorded here in words so
  # the next person meets it as a known defect rather than a discovery.
  def test_gear_patches_are_reachable_from_a_pool
    result = eval_in_engine(<<~RUBY)
      # Comments stripped first. Counting raw occurrences cannot tell a pool
      # entry from prose, and this test failed on arrival because a comment
      # elsewhere in the file NAMED minimoog_bass while explaining that it is
      # unreachable -- the mention made it look reached.
      src = engine_source.lines.reject { |l| l =~ /\\A\\s*#/ }.join
      gear = %i[voyager_ladder_pad voyager_mono_lead microkorg_lead
                microkorg_vox_texture access_virus_hyper motif_rack_strings motif_rack_ep]
      puts JSON.generate(
        defined: gear.select { |id| !synth_patch_by_id(id).nil? },
        # More than one occurrence means the id is named somewhere beyond its
        # own synth_patch(...) definition -- a pool, a preset or a cycle.
        orphans: gear.select { |id| src.scan(/\\b\#{id}\\b/).length < 2 },
        catalog: SYNTH_PATCH_CATALOG.length,
        bass_role: SYNTH_PATCH_CATALOG.select { |p| p[:role] == :bass }.map { |p| p[:id] },
        bass_orphaned: SYNTH_PATCH_CATALOG.select { |p| p[:role] == :bass }
                                          .all? { |p| src.scan(/\\b\#{p[:id]}\\b/).length < 2 }
      )
    RUBY

    assert_equal 7, result.fetch("defined").length, "every gear patch must load"
    assert_empty result.fetch("orphans"),
                 "a patch named in no pool can never be selected, however good it sounds"
    assert_operator result.fetch("catalog"), :>=, 212

    # Documented, not asserted away: if someone wires the bass role up, this
    # flips and the comment above needs deleting rather than the test relaxing.
    assert result.fetch("bass_orphaned"),
           "role :bass is currently unreachable; if that changed, update the note on this test"
  end

  # Two chord tables, one engine.
  #
  # dilla.rb::CHORD_TEMPLATES (15 symbols) feeds chord_from_quality;
  # DillaProducerDNA::CHORD_TEMPLATES (46) feeds build_voicing. Both are live,
  # so a symbol spelled differently in the two is a chord whose actual notes
  # depend on which path the render happened to take.
  #
  # Measured: exactly one disagreement, "7alt" -- [0,4,7,10,1] here against
  # [0,4,8,10,1] there. A perfect fifth at 7 makes it a 7b9, not an altered
  # dominant, so half the engine played a chord that was not the one named.
  #
  # This pins agreement rather than merging the tables: the larger one carries
  # 31 symbols the smaller does not, and several callers iterate the smaller as
  # a validation set.
  def test_chord_tables_agree_on_every_shared_symbol
    result = eval_in_engine(<<~RUBY)
      a = CHORD_TEMPLATES
      b = DillaProducerDNA::CHORD_TEMPLATES
      shared = a.keys & b.keys
      puts JSON.generate(
        shared: shared.length,
        disagreeing: shared.reject { |k| a[k] == b[k] }.sort,
        alt_here: a["7alt"], alt_there: b["7alt"]
      )
    RUBY
    assert_operator result.fetch("shared"), :>=, 15, "the tables should still overlap"
    assert_empty result.fetch("disagreeing"),
                 "a symbol spelled two ways renders as two different chords depending on path"
    # An altered dominant has no perfect fifth. Pinned directly so a future
    # edit cannot make both tables agree on the WRONG spelling and still pass.
    refute_includes result.fetch("alt_here"), 7, "7alt must not carry a natural fifth"
    refute_includes result.fetch("alt_there"), 7, "7alt must not carry a natural fifth"
  end

  # A persisted composition session used to outrank the caller completely.
  #
  # composition_session! computed a performer and a groove from ENV and then
  # called Session.load!, which had no parameter for either -- so both locals
  # were discarded and the identity came entirely from project/session.json.
  # A track preset saying PERFORMER => yancey, or an operator typing it on the
  # command line, was read, ignored, and reported back as whatever the last
  # evolve left on disk. The track went the same way.
  #
  # It is not a small cosmetic difference: performer and groove_dna drive the
  # microtiming offsets in dilla_timing_ms, so they are the pocket. A 26-track
  # demo rendered 18 non-techno parts all at questlove/cosmogramma/gen59, which
  # is most of why a catalogue of distinct progressions sounded like one beat.
  #
  # Both directions matter. An explicit ask must win, and NO ask must still
  # resume the file -- otherwise every render silently resets an evolved
  # session's identity to a default nobody chose, which is the same class of bug
  # pointing the other way.
  def test_explicit_performer_beats_the_persisted_session
    result = eval_in_engine(<<~RUBY)
      require "fileutils"
      require "json"
      path = DillaComposition::SESSION_PATH
      FileUtils.mkdir_p(File.dirname(path))
      saved = File.exist?(path) ? File.read(path) : nil
      File.write(path, JSON.generate(
        "track" => "neo_soul", "performer" => "questlove",
        "groove_dna" => "cosmogramma", "generation" => 59, "best_score" => 0.5
      ))
      begin
        %w[PERFORMER GROOVE_DNA TRACK].each { |k| ENV.delete(k) }
        reset_composition_session!
        kept = composition_session!(n_bars: 8)

        ENV["PERFORMER"] = "yancey"
        ENV["GROOVE_DNA"] = "donuts"
        ENV["TRACK"] = "semua_untuk_mu"
        reset_composition_session!
        asked = composition_session!(n_bars: 8, track: "semua_untuk_mu")

        puts JSON.generate(
          kept: { performer: kept.performer.to_s, groove: kept.groove_dna.to_s,
                  track: kept.track.to_s, generation: kept.generation },
          asked: { performer: asked.performer.to_s, groove: asked.groove_dna.to_s,
                   track: asked.track.to_s, generation: asked.generation }
        )
      ensure
        saved ? File.write(path, saved) : FileUtils.rm_f(path)
      end
    RUBY

    asked = result.fetch("asked")
    assert_equal "yancey", asked["performer"], "an explicit PERFORMER must reach the session"
    assert_equal "donuts", asked["groove"], "an explicit GROOVE_DNA must reach the session"
    assert_equal "semua_untuk_mu", asked["track"], "an explicit TRACK must reach the session"
    assert_equal 59, asked["generation"],
                 "the evolved material must survive -- this overrides the identity, not the session"

    kept = result.fetch("kept")
    assert_equal "questlove", kept["performer"],
                 "with nothing asked for, the persisted session still wins; otherwise every " \
                 "render quietly resets an evolved session to a default nobody chose"
    assert_equal "cosmogramma", kept["groove"]
    assert_equal "neo_soul", kept["track"]
  end

  # demo-all reassigns a share of its slots to render_hate_techno, which builds
  # its own arrangement and never calls sample_loop_for. Reassigning a track that
  # carries a sampled bed therefore returns a techno piece with the record
  # absent, and nothing in the log distinguishes that from the sample having
  # played. At the 0.34 default it was a third of every hand-cut and chopped
  # loop. The bed IS the reason those tracks exist, so they are exempt at any
  # share -- including DEMO_TECHNO_SHARE=1.
  def test_sampled_beds_are_never_reassigned_to_the_techno_renderer
    result = eval_in_engine(<<~RUBY)
      # Aliases whose target is actually in the rack. An alias pointing at a
      # loop the crate does not have is not a sampled bed — there is no sample
      # to lose — and counting it as one made this test assert that the engine
      # protects a record that is not there. The crate was cleared on the
      # operator's call in 74d9e4c1b and is being rebuilt from source, so the
      # eight sheger_* aliases resolve to nothing until it lands.
      live_aliases = TRACK_SAMPLE_LOOP_ALIASES.select { |_, target| TRACK_SAMPLE_LOOPS.key?(target) }
      beds = TRACK_SAMPLE_LOOPS.keys.map(&:to_s) + live_aliases.keys.map(&:to_s)
      # With TECHNO_HARMONY off the techno renderer cannot carry a bed, so no
      # sampled track may be reassigned at any share.
      ENV.delete("TECHNO_HARMONY")
      stolen = { "default" => nil, "1.0" => "1", "0.34" => "0.34" }.filter_map do |label, share|
        share ? ENV["DEMO_TECHNO_SHARE"] = share : ENV.delete("DEMO_TECHNO_SHARE")
        hit = beds.each_with_index.select { |slug, i| demo_techno_slot?(i, slug) }.map(&:first)
        [label, hit] unless hit.empty?
      end
      ENV.delete("DEMO_TECHNO_SHARE")
      # With it on the bed IS carried, so the exemption must lift -- otherwise a
      # sampled record could never become a techno track, which is the thing the
      # whole genre-agnostic direction exists to allow.
      ENV["TECHNO_HARMONY"] = "1"
      ENV["DEMO_TECHNO_SHARE"] = "1"
      lifted = beds.each_with_index.count { |slug, i| demo_techno_slot?(i, slug) }
      ENV.delete("TECHNO_HARMONY")
      ENV.delete("DEMO_TECHNO_SHARE")
      # Non-sample tracks must still be eligible, or the guard is an off
      # switch. Counted across the real catalogue rather than probed at one
      # slug: whether any single track hashes into a slot is luck, and a
      # control that narrow fails for reasons that have nothing to do with the
      # guard.
      plain = (TRACK_PRESETS.keys.map(&:to_s) - beds).first(40)
      eligible = plain.each_with_index.count { |slug, i| demo_techno_slot?(i, slug) }
      puts JSON.generate(builtin_count: TRACK_SAMPLE_LOOPS_BUILTIN.length, stolen: stolen, bed_count: beds.length, lifted: lifted,
                         plain_sampled: plain.length, plain_eligible: eligible)
    RUBY
    # 12 is the populated-crate number. With the crate cleared the builtin
    # loops are all there is, and asserting the full count would fail the suite
    # on the state the operator deliberately put the tree in.
    assert_operator result.fetch("bed_count"), :>=, result.fetch("builtin_count")
    assert_empty result.fetch("stolen"),
                 "sampled beds reassigned to techno, so the sample never plays: #{result.fetch('stolen').inspect}"
    assert_operator result.fetch("lifted"), :>, 0,
                    "with TECHNO_HARMONY on the techno renderer carries the bed, so the exemption must lift — " \
                    "otherwise a sampled record can never become a techno track"
    assert_operator result.fetch("plain_eligible"), :>, 0,
                    "the guard must exempt sampled beds, not disable techno slots altogether " \
                    "(0 of #{result.fetch('plain_sampled')} plain tracks were eligible)"
  end

  # CHORD_SUFFIXES is the parser's whitelist; CHORD_TEMPLATES is what voices the
  # match. A suffix listed in the first and missing from the second does not
  # raise -- quality_for_suffix falls back to "maj9", so the symbol parses and
  # renders as the wrong chord, silently. That is how a written 7#9 could come
  # out a major ninth. Pin the two tables to each other.
  #
  # Also pins that no suffix contains "/": uncached_chord_from_symbol
  # short-circuits any symbol with a slash into slash_chord_from_symbol before
  # the suffix matcher runs, so such an entry is unreachable, and the symbol it
  # advertises ("C6/9") raises KeyError on the bass-note lookup instead.
  def test_chord_suffixes_all_have_a_template_and_no_suffix_carries_a_slash
    result = eval_in_engine(<<~RUBY)
      m = DillaLofiMachine
      named = m::CHORD_SUFFIXES.reject(&:empty?)
      puts JSON.generate(
        count: named.length,
        untemplated: named.reject { |s| m::CHORD_TEMPLATES.key?(s) || m::QUALITY_ALIASES.key?(s) },
        with_slash: named.select { |s| s.include?("/") },
        tones: named.to_h do |s|
          hz = m.chord_from_symbol("C" + s)[:hz] rescue nil
          [s, hz&.map { |f| (69.0 + (12.0 * Math.log2(f / 440.0))).round % 12 }&.uniq&.sort]
        end
      )
    RUBY
    assert_operator result.fetch("count"), :>=, 40
    assert_empty result.fetch("untemplated"),
                 "suffixes with no template voice as maj9 -- the wrong chord, without an error"
    assert_empty result.fetch("with_slash"),
                 "a suffix containing / can never be reached: the slash branch runs first"
    unreachable = result.fetch("tones").select { |_, pcs| pcs.nil? }.keys
    assert_empty unreachable, "every listed suffix must parse as a chord"
  end

  # The trim in build_voicing keeps the root and the highest four, so a
  # six-interval template loses its lowest extension -- which on a dominant is
  # the third, half the tritone that defines it. Every altered dominant here
  # must still contain the tones its name claims.
  def test_altered_dominants_keep_the_tones_they_are_named_for
    result = eval_in_engine(<<~RUBY)
      want = { "7#9" => [4, 10, 3], "7b13" => [4, 10, 8], "13b9" => [4, 10, 1, 9],
               "13#11" => [4, 10, 6, 9], "7#9#11" => [4, 10, 3, 6],
               "7#9b13" => [4, 10, 3, 8], "maj7#9" => [4, 11, 3],
               "maj9#11" => [4, 11, 2, 6], "m9b5" => [3, 6, 10, 2],
               "m11b5" => [3, 6, 10, 5], "m13" => [3, 10, 9], "69" => [4, 9, 2] }
      missing = want.filter_map do |sfx, tones|
        pcs = DillaLofiMachine.chord_from_symbol("C" + sfx)[:hz]
                              .map { |f| (69.0 + (12.0 * Math.log2(f / 440.0))).round % 12 }
        gone = tones.map { |t| t % 12 } - pcs
        ["C" + sfx, gone] unless gone.empty?
      end
      puts JSON.generate(missing: missing)
    RUBY
    assert_empty result.fetch("missing"),
                 "altered dominants dropped defining tones: #{result.fetch('missing').inspect}"
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

  def test_rap_vocal_blocklist_skips_sirkel_sag_on_stream
    result = eval_in_engine(<<~RUBY)
      ENV["RAP_VOCAL"] = "sirkel_sag"
      puts JSON.generate(
        blocklisted: RAP_VOCAL_BLOCKLIST.include?("sirkel_sag"),
        stream: rap_vocal_stream_slug
      )
    RUBY
    assert result.fetch("blocklisted"), "sirkel_sag must stay on RAP_VOCAL_BLOCKLIST"
    assert_nil result.fetch("stream"), "blocklisted slugs never auto-mix on stream"
  end

  # A pinned pad voice must not pin the progression.
  #
  # `STREAM_TRACK=slum_village_players_documented PAD_VOICE=prophet` rendered the
  # documented transcription's name at its documented 91 BPM while playing
  # pedal_e_descent's chords, because stream()'s guard skipped
  # `ENV["PROGRESSION"] = track` whenever a pad key was set and PROGRESSION was
  # non-empty — and apply_best_defaults! guarantees it is never empty.
  def test_pinned_pad_voice_does_not_freeze_the_progression_on_the_default_track
    result = eval_in_engine(<<~RUBY)
      ENV["PAD_VOICE"] = "prophet"
      apply_best_defaults!
      before = ENV["PROGRESSION"]
      sync_progression_to_track!("slum_village_players_documented")
      ENV["TRACK"] = "slum_village_players_documented"
      cfg = dilla_resolve_config
      puts JSON.generate(
        best_default: before,
        after_sync: ENV["PROGRESSION"],
        cfg_progression: cfg[:progression].to_s,
        chords: dilla_progression(cfg[:progression]).map { |c| c[:name].to_s },
        curated: curated_progression?(cfg)
      )
    RUBY
    refute_empty result.fetch("best_default"),
      "premise: best defaults fill PROGRESSION, so it is never empty"
    assert_equal "slum_village_players_documented", result.fetch("after_sync")
    assert_equal "slum_village_players_documented", result.fetch("cfg_progression")
    assert result.fetch("curated"), "a documented transcription loops, it is not developed"
    assert_equal %w[Cm9 Fm9 Bb13 Ebmaj7 Abmaj7 Dm7b5 G7alt Cm9], result.fetch("chords"),
      "the transcribed chords, not pedal_e_descent's chromatic descent"
  end

  # The other half of the same guard: an explicitly pinned PROGRESSION survives
  # the per-track sync, which is what USER_PINNED_ENV exists to protect.
  def test_explicitly_pinned_progression_survives_the_track_sync
    result = eval_in_engine(<<~RUBY)
      # USER_PINNED_ENV is captured at load, so pin through it the way a real
      # command line would.
      pinned = USER_PINNED_ENV.dup
      pinned["PROGRESSION"] = "pedal_e_descent"
      Object.send(:remove_const, :USER_PINNED_ENV)
      Object.const_set(:USER_PINNED_ENV, pinned.freeze)
      ENV["PROGRESSION"] = "pedal_e_descent"
      sync_progression_to_track!("slum_village_players_documented")
      puts JSON.generate(progression: ENV["PROGRESSION"])
    RUBY
    assert_equal "pedal_e_descent", result.fetch("progression")
  end

  def test_dilla_style_locks_color_and_disables_self_sample
    result = eval_in_engine(<<~RUBY)
      ENV["DILLA_STREAMING"] = "1"
      ENV["RENDER_MODE"] = "dilla"
      apply_dilla_style!(force: true)
      puts JSON.generate(
        mode: ENV["RENDER_MODE"],
        sonitex: ENV["SONITEX"],
        analog: ENV["ANALOG_CHAIN"],
        vinyl: ENV["VINYL"],
        self_sample: ENV["SELF_SAMPLE"],
        lock: ENV["CAMEL_LOCK_COLOR"],
        wild: ENV["STREAM_ANALOG_WILD"],
        morph: ENV["SYNTH_MORPH"],
        creative: ENV["STREAM_CREATIVE_FREEDOM"]
      )
    RUBY
    assert_equal "dilla", result.fetch("mode")
    # DILLA_STYLE_DEFAULTS carries donuts_warm/vinyl_hot/VINYL=1 (see the
    # comment on DILLA_BEST_DEFAULTS' own donuts_soul/broadcast entries --
    # that table intentionally keeps the safer values for callers that don't
    # go through apply_dilla_style!(force: true); this test does).
    assert_equal "donuts_warm", result.fetch("sonitex")
    assert_equal "vinyl_hot", result.fetch("analog")
    assert_equal "1", result.fetch("vinyl")
    assert_equal "0", result.fetch("self_sample")
    assert_equal "1", result.fetch("lock")
    assert_equal "0", result.fetch("wild")
    # Style table cycles patches + morph for stream color (see DILLA_STYLE_DEFAULTS).
    assert_equal "1", result.fetch("morph")
    assert_equal "1", result.fetch("creative")
  end

  def test_lead_arp_zero_wins_even_when_pad_arp_is_wash
    result = eval_in_engine(<<~RUBY)
      ENV["PAD_ARP_MODE"] = "wash"
      ENV["LEAD_ARP"] = "0"
      ENV["HARMONY_LEAD"] = "0"
      puts JSON.generate(lead: lead_arp_enabled?, harmony: harmony_lead_enabled?)
    RUBY
    refute result.fetch("lead"), "LEAD_ARP=0 must disable lead_arp_enabled?"
    refute result.fetch("harmony")
  end

  def test_dilla_style_stack_pad_and_lead_defaults
    result = eval_in_engine(<<~RUBY)
      ENV["DILLA_STREAMING"] = "1"
      apply_dilla_style!(force: true)
      stack = PAD_LAYER_STACKS[ENV["PAD_VOICE"]&.to_sym]
      puts JSON.generate(
        track: ENV["TRACK"],
        pad_voice: ENV["PAD_VOICE"],
        pad_layers: ENV["PAD_LAYERS"],
        stack_n: stack&.length || 0,
        pad_vol: ENV["PAD_VOL"].to_i,
        lead_arp: ENV["LEAD_ARP"],
        lead_mode: ENV["LEAD_ARP_MODE"],
        lead_voice: ENV["LEAD_VOICE"],
        lead_on: lead_arp_enabled?,
        lead_vol: ENV["HARMONIC_LEAD_ARP_VOLUME"].to_f,
        morph: ENV["SYNTH_MORPH"],
        roles: DillaComposition::ENSEMBLE_TIMELINE[:verse].map(&:to_s)
      )
    RUBY
    assert_equal "slum_village_intro_documented", result.fetch("track")
    assert_equal "moog", result.fetch("pad_voice")
    assert_equal "1", result.fetch("pad_layers")
    # moog is a single analog voice, not a stack -- that is the point of it
    # (e65f717be): one voice for STREAM_ROTATE_SYNTH to cycle, the fat analog
    # opposite of the Rhodes/Prophet electric-piano stack this used to assert.
    assert_equal 0, result.fetch("stack_n")
    # LEAD_ARP is on by default (0a77242dd), and the arp volume is what that
    # signature lead is mixed at.
    assert_equal "1", result.fetch("lead_arp")
    assert result.fetch("lead_on")
    assert_operator result.fetch("lead_vol"), :>=, 1.5
    assert_equal "1", result.fetch("morph"), "style defaults keep SYNTH_MORPH on for mid-phrase color"
    assert_includes result.fetch("roles"), "lead"
    assert_includes result.fetch("roles"), "scale_lead"
  end

  def test_experimental_pad_voices_and_leads_resolve
    result = eval_in_engine(<<~RUBY)
      voices = %i[glass vapor crystal ice neon pulse]
      bad_pad = voices.reject { |v| PAD_VOICE_PRESETS[v] && synth_patch_by_id(PAD_VOICE_PRESETS[v][:warm]) }
      leads = %i[glass vapor crystal acid neon]
      bad_lead = leads.reject { |v| LEAD_VOICE_PRESETS[v] && synth_patch_by_id(LEAD_VOICE_PRESETS[v]) }
      arps = %i[glass_spin vapor_wave acid_run crystal_scatter]
      bad_arp = arps.reject { |a| LEAD_ARP_PRESETS[a] }
      apply_dilla_style!(force: true)
      puts JSON.generate(
        bad_pad: bad_pad.map(&:to_s),
        bad_lead: bad_lead.map(&:to_s),
        bad_arp: bad_arp.map(&:to_s),
        morph_voices: PAD_VOICE_MORPH_VOICES.map(&:to_s),
        morph: ENV["SYNTH_MORPH"],
        exp: ENV["EXPERIMENTAL_LEADS"],
        pad: ENV["PAD_VOICE"],
        stack: PAD_LAYER_STACKS[:stack_soul]&.length || 0
      )
    RUBY
    assert_empty result.fetch("bad_pad")
    assert_empty result.fetch("bad_lead")
    assert_empty result.fetch("bad_arp")
    assert_includes result.fetch("morph_voices"), "glass"
    # SYNTH_MORPH=1 is fine: multi-layer stack still wins while PAD_LAYERS=1.
    assert_equal "1", result.fetch("morph")
    # EXPERIMENTAL_LEADS went 1 -> 0 in cd8e6850f with the rest of the lead
    # layers. The presets above must still all resolve — that is what this test
    # is for — but the style DNA does not switch them on.
    assert_equal "0", result.fetch("exp")
    assert_equal "moog", result.fetch("pad")
    assert_operator result.fetch("stack"), :>=, 3
  end

  EXPANSION_TRACKS = %w[
    lydian_glass_cycle pedal_upper_structures bossa_major9_turn phrygian_gold_arc
    two_chord_luminous mixo_sus_loop common_tone_drift third_cycle_triads
    drone_quartal_wash waltz_relative_lift half_time_gospel_plagal double_time_pocket
    whole_tone_bridge upper_triad_tower minor_add9_lullaby dominant_chain_home
  ].freeze

  def test_expansion_pack_tracks_resolve_progressions_and_rotation
    result = eval_in_engine(<<~RUBY)
      tracks = #{EXPANSION_TRACKS.inspect}
      bad = tracks.filter_map do |t|
        ENV["TRACK"] = t
        pads = DillaLofiMachine.progression_for(t) || curated_progression_pads(t)
        next t if pads.nil? || pads.length < 2
        nil
      end
      missing_rot = tracks.reject { |t| DillaLofiMachine::STREAM_ROTATION.include?(t) }
      missing_soul = tracks.reject { |t| DillaHarmony::SOUL_PROFILES.map(&:to_s).include?(t) }
      puts JSON.generate(
        bad: bad,
        missing_rot: missing_rot,
        missing_soul: missing_soul,
        rotation_n: DillaLofiMachine::STREAM_ROTATION.size,
        sample: (DillaLofiMachine.progression_for("lydian_glass_cycle") || []).map { |c| c[:name] }
      )
    RUBY
    assert_empty result.fetch("bad"), "progressions failed: #{result['bad']}"
    assert_empty result.fetch("missing_rot")
    assert_empty result.fetch("missing_soul")
    assert_operator result.fetch("rotation_n"), :>=, 60
    assert_includes result.fetch("sample"), "Fmaj9"
  end

  def test_dilla_default_progression_has_no_planing_names
    result = eval_in_engine(<<~RUBY)
      ENV["RENDER_MODE"] = "dilla"
      ENV["LA_BEAT_PROGRESSION"] = "0"
      ENV["DILLA_STREAMING"] = "1"
      apply_dilla_style!(force: true)
      pads = dilla_progression(ENV["PROGRESSION"] || ENV["TRACK"])
      names = pads.map { |c| c[:name].to_s }
      puts JSON.generate(names: names, planing: names.any? { |n| n.start_with?("planing") })
    RUBY
    refute result.fetch("planing"), "default progression must not use planing* chords"
    assert_operator result.fetch("names").length, :>=, 4
  end

  def test_stream_iterate_tuning_soft_fill_does_not_clobber_style
    result = eval_in_engine(<<~RUBY)
      ENV["DILLA_STREAMING"] = "1"
      ENV["SONITEX"] = "donuts_soul"
      ENV.delete("STREAM_CREATIVE_FREEDOM")
      soft_fill_iterate!(
        { "SONITEX" => "heavy", "STREAM_CREATIVE_FREEDOM" => "1" },
        locked_keys: %w[SONITEX]
      )
      puts JSON.generate(sonitex: ENV["SONITEX"], creative: ENV["STREAM_CREATIVE_FREEDOM"])
    RUBY
    assert_equal "donuts_soul", result.fetch("sonitex")
    assert_equal "1", result.fetch("creative"), "unlocked iterate keys still soft-fill when empty"
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

  # A part with no signal must not reach the concat. demo_report_suspect_parts
  # names quiet and short parts, but it runs after the join -- twice now a
  # -91 dB placeholder was warned about only once it was already inside the
  # shipped demo. This gate is absolute and narrow: dead, not merely quiet.
  def test_dead_parts_are_dropped_before_the_join_but_quiet_ones_are_kept
    result = eval_in_engine(<<~RUBY)
      dir = Dir.mktmpdir
      make = lambda do |name, filter|
        path = File.join(dir, name)
        sh! "ffmpeg", "-y", "-loglevel", "error", "-f", "lavfi", "-i", filter,
            "-ac", "2", "-ar", "44100", "-t", "2", path
        path
      end
      dead = make.call("dead.wav", "anullsrc=r=44100:cl=stereo")
      quiet = File.join(dir, "quiet.wav")
      sh! "ffmpeg", "-y", "-loglevel", "error", "-f", "lavfi", "-i", "sine=f=220:d=2",
          "-ac", "2", "-ar", "44100", "-af", "volume=-45dB", quiet
      loud = make.call("loud.wav", "sine=f=220:d=2")

      puts JSON.generate(
        dead_flagged: demo_part_dead?(dead),
        quiet_flagged: demo_part_dead?(quiet),
        loud_flagged: demo_part_dead?(loud),
        kept: demo_reject_dead_parts([dead, quiet, loud]).map { |f| File.basename(f) },
        all_dead: demo_reject_dead_parts([dead]).length,
        missing_flagged: demo_part_dead?(File.join(dir, "does_not_exist.wav"))
      )
    RUBY

    assert result.fetch("dead_flagged"), "digital silence must be flagged"
    refute result.fetch("quiet_flagged"), "-45 dB is quiet, not dead — a legitimate take"
    refute result.fetch("loud_flagged")

    assert_equal %w[quiet.wav loud.wav], result.fetch("kept")

    # Joining an empty list writes a zero-length file that every downstream step
    # accepts, so an all-dead input must hand the parts back untouched and let
    # the join fail loudly instead.
    assert_equal 1, result.fetch("all_dead")

    # A file ffmpeg cannot measure is not provably dead. After hours of
    # rendering, keep it and let the suspect report name it.
    refute result.fetch("missing_flagged"), "unmeasurable must not count as dead"
  end

  # DEMO_INSTRUMENTAL_EVERY has to be additive: it holds slots back from
  # whatever DEMO_RAP_EVERY already decided, and defaults to changing nothing.
  # A knob that silently altered the default demo would be worse than no knob.
  def test_demo_instrumental_every_holds_back_slots_without_changing_the_default
    result = eval_in_engine(<<~RUBY)
      run = lambda do |rap_every, instrumental|
        ENV["DEMO_INSTRUMENTAL_EVERY"] = instrumental.to_s
        (0...34).select { |i| demo_rap_slot?(i, rap_every) }
      end
      puts JSON.generate(
        default: run.call(1, 0),
        held: run.call(1, 6),
        every_other: run.call(2, 0),
        every_other_held: run.call(2, 6),
        rap_off: run.call(0, 6)
      )
    RUBY

    # Default (0) is off: every slot rap_every allows still carries a rapper.
    assert_equal (0...34).to_a, result.fetch("default")

    # Additive, not a replacement: the held slots are exactly those dropped.
    held = result.fetch("held")
    assert_equal [5, 11, 17, 23, 29], (0...34).to_a - held
    assert_equal 29, held.size, "most slots should still carry a rapper"

    # It narrows an existing selection rather than widening it.
    every_other = result.fetch("every_other")
    assert_equal every_other - [5, 11, 17, 23, 29], result.fetch("every_other_held")

    # DEMO_RAP_EVERY=0 means no vocals anywhere and still wins.
    assert_empty result.fetch("rap_off")
  end

  # "No leads" took six rounds to achieve, because each attempt turned off the
  # layer that had been named and the renderer had another one. HATE_TONAL=0 is
  # the single switch; this pins that it reaches every pitched layer and that it
  # is inert unless asked for.
  def test_hate_tonal_zero_silences_every_pitched_layer
    result = eval_in_engine(<<~RUBY)
      keys = HATE_TONAL_LAYERS
      keys.each { |k| ENV.delete(k) }
      ENV.delete("HATE_TONAL")
      untouched = { fired: hate_forbid_tonal!, values: keys.to_h { |k| [k, ENV[k]] } }

      keys.each { |k| ENV.delete(k) }
      ENV["HATE_TONAL"] = "0"
      forbidden = { fired: hate_forbid_tonal!, values: keys.to_h { |k| [k, ENV[k]] } }

      # An explicit 1 must not be able to switch anything ON by accident.
      keys.each { |k| ENV.delete(k) }
      ENV["HATE_TONAL"] = "1"
      on = { fired: hate_forbid_tonal!, values: keys.to_h { |k| [k, ENV[k]] } }

      puts JSON.generate(layers: keys, untouched:, forbidden:, on:)
    RUBY

    # The list has to cover the layers that actually carry pitch.
    assert_equal %w[HATE_MELODY HATE_DFAM HATE_DRONE], result.fetch("layers")

    # Unset: inert. A default that quietly muted layers would be worse than none.
    refute result.dig("untouched", "fired")
    assert result.dig("untouched", "values").values.all?(&:nil?),
           "HATE_TONAL unset must not write any layer key"

    # Zero: every one of them off, in one call.
    assert result.dig("forbidden", "fired")
    assert_equal %w[0 0 0], result.dig("forbidden", "values").values_at(*result.fetch("layers"))

    # One: still inert -- this switch only ever subtracts.
    refute result.dig("on", "fired")
    assert result.dig("on", "values").values.all?(&:nil?)
  end

  def test_flylo_drum_overlay_schedules_dual_bus_events
    result = eval_in_engine(<<~RUBY)
      %w[RENDER_MODE CAMEL_DRUM_LOCK PRODUCER_MODE].each { |k| ENV.delete(k) }
      ENV["WONKY_DRUM_OVERLAY"] = "1"
      # Dead switch: nothing in lib reads QUINT_HATS under either prefix, so
      # this sets nothing and the quint assertion below passes because quint
      # is never scheduled at all. Left as-is rather than renamed -- a
      # differently-named dead switch is not an improvement. See TODO.md.
      ENV["FLYLO_QUINT_HATS"] = "1"
      ENV["KICKS"] = "1"
      ENV["CAMEL_DRUM_LOCK"] = "0"
      pads = curated_progression_pads(:fourth_third_sixth_second_turn) ||
             [{ name: "Dbmaj9", hz: [58.0, 73.0, 87.0] }, { name: "Cm9", hz: [55.0, 65.0, 82.0] }]
      beat_p = 60.0 / 88.0
      events = dilla_schedule(8, beat_p, pads, chord_bars: 2, feel: :timeless, swing: 57.0)
      puts JSON.generate(
        wonky_kick: events[:wonky_kick]&.length.to_i,
        wonky_hat: events[:wonky_hat]&.length.to_i,
        wonky_snare: events[:wonky_snare]&.length.to_i,
        # Quint/perc intentionally omitted (sparse overlay — no spam).
        wonky_quint: events[:wonky_quint]&.length.to_i,
        enabled: wonky_drum_overlay_enabled?
      )
    RUBY
    assert result.fetch("enabled")
    assert_operator result.fetch("wonky_kick"), :>, 0
    assert_operator result.fetch("wonky_hat"), :>, 0
    assert_operator result.fetch("wonky_snare"), :>, 0
    assert_equal 0, result.fetch("wonky_quint"), "sparse overlay skips quint spam"
  end

  def test_stream_iterate_evolve_wonky_drums_returns_notes
    result = eval_in_engine(<<~RUBY)
      ENV["WONKY_DRUM_OVERLAY"] = "1"
      ENV["DILLA_STREAMING"] = "1"
      ENV["STREAM_ITERATE"] = "1"
      ENV["STREAM_WONKY_EVERY"] = "1"
      @stream_iterate_count = 2
      notes = stream_iterate_evolve_wonky_drums!
      puts JSON.generate(
        notes: notes,
        gain: ENV["WONKY_OVERLAY_GAIN"],
        grid: ENV["WONKY_GRID_BIAS"]
      )
    RUBY
    assert result.fetch("notes").any? { |n| n.start_with?("wonky_gain=") }
    assert result.fetch("gain").to_s.length.positive?
    assert result.fetch("grid").to_s.length.positive?
  end

  def test_stream_iterate_harmony_and_analog_return_notes_when_due
    result = eval_in_engine(<<~RUBY)
      %w[RENDER_MODE CAMEL_LOCK_COLOR PRODUCER_MODE CAMEL_DRUM_LOCK].each { |k| ENV.delete(k) }
      ENV["DILLA_STREAMING"] = "1"
      ENV["STREAM_ITERATE"] = "1"
      ENV["STREAM_HARMONY_EVERY"] = "1"
      ENV["STREAM_ANALOG_EVERY"] = "1"
      ENV["CAMEL_LOCK_COLOR"] = "0"
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
    # These are not five unconditional asserts, which made this test a coin
    # flip — the single largest source of this suite's nondeterminism (identical
    # `rake test` runs alternated between 3 and 4 failures).
    #
    # Why: stream_iterate_evolve_harmony! seeds its RNG from
    # Time.now.to_i + Process.pid + @stream_iterate_count, then only assigns
    # ENV["TRACK"]/["VOICING"] inside `elsif rng.rand < 0.55` (or a 0.35 branch).
    # So roughly half of all runs legitimately set nothing, and asserting that
    # they always do was asserting the dice.
    #
    # What is actually contractual: both calls return a note array, and any state
    # a note *claims* must be present in ENV. That is the invariant worth
    # guarding — a note saying "voicing=x" while ENV carries nothing would be a
    # real bug, and this still catches it.
    #
    # To restore the strong assertions, the engine needs a seedable RNG (e.g. a
    # DILLA_SEED env read in place of the Time/pid seed). That belongs in
    # STUDIO/dilla/dilla.rb, not here.
    harm = result.fetch("harm")
    analog = result.fetch("analog")
    assert_kind_of Array, harm
    assert_kind_of Array, analog

    # One note per claim. A `voicing=` note is emitted unconditionally, while
    # ENV[TRACK] is only assigned inside the two probabilistic branches
    # (`track=` / `promoted=`), so keying the TRACK assertion off `voicing=` left
    # this test a coin flip after all — it still failed about once per suite run.
    if harm.any? { |n| n.start_with?("voicing=") }
      assert result.fetch("voicing").to_s.length.positive?, "reported a voicing change but ENV[VOICING] is empty"
    end

    if harm.any? { |n| n.start_with?("track=", "promoted=") }
      assert result.fetch("track").to_s.length.positive?, "reported a track change but ENV[TRACK] is empty"
    end

    return unless analog.any? { |n| n.start_with?("analog=") }
      assert result.fetch("analog_chain").to_s.length.positive?, "reported an analog change but ENV[ANALOG_CHAIN] is empty"

  end

  def test_dilla_sidechain_style_selects_fast_duck_for_dilla_family
    result = eval_in_engine(<<~RUBY)
      # Filter choice is ENV SIDECHAIN_STYLE (not style_family alone).
      ENV["SIDECHAIN_STYLE"] = "dilla"
      dilla = sidechain_filter_chain({ style_family: :dilla })
      ENV["SIDECHAIN_STYLE"] = "flylo"
      flylo = sidechain_filter_chain({ style_family: :flylo })
      puts JSON.generate(
        dilla_release: dilla.join.include?("release=90"),
        flylo_release: flylo.join.include?("release=28")
      )
    RUBY
    assert result.fetch("dilla_release"), "dilla sidechain should use tight release=90"
    assert result.fetch("flylo_release"), "flylo sidechain uses release=28 (smoother duck)"
  end

  def test_mix_metrics_returns_band_levels_when_demo_present
    demo = File.expand_path("../dilla/demo.wav", __dir__)
    skip "demo.wav missing" unless File.file?(demo)
    skip "ffmpeg not available" unless system("which ffmpeg > /dev/null 2>&1")
    result = eval_in_engine(<<~RUBY)
      m = mix_metrics(#{demo.dump})
      puts JSON.generate(m)
    RUBY
    assert result.key?("peak_db")
    assert result.key?("air_db")
    assert result.key?("pad_body_db")
  end

  # The shipped artifact, not the parts.
  #
  # demo_reject_dead_parts guards the join, but only for parts it is handed. A
  # demo assembled some other way, or a mastering stage that emits nothing, can
  # still put a dead stretch in demo.mp3 -- and nothing looks at demo.mp3 after
  # it is written. Twice a -91 dB placeholder reached a demo; both times it was
  # found by listening, not by a test.
  #
  # One decode, two filters. Deliberately loose bounds: this is a smoke gate for
  # "the demo is broken", not a taste judgement, and a demo the operator
  # deliberately masters differently should not fail it.
  def test_shipped_demo_has_no_dead_stretch_and_lands_near_its_loudness_target
    demo = File.expand_path("../dilla/demo.mp3", __dir__)
    skip "demo.mp3 missing" unless File.file?(demo)
    skip "ffmpeg not available" unless system("which ffmpeg > /dev/null 2>&1")

    out = `ffmpeg -hide_banner -nostats -i #{demo.dump} -af silencedetect=n=-70dB:d=5,ebur128 -f null - 2>&1`

    dead = out.scan(/silence_duration:\s*([\d.]+)/).flatten.map(&:to_f)
    assert_empty dead.select { |d| d >= 5.0 },
                 "demo.mp3 contains #{dead.length} silent stretch(es) of 5s or more " \
                 "(longest #{dead.max}s) -- a dead part reached the master"

    integrated = out.scan(/I:\s*(-?[\d.]+)\s*LUFS/).flatten.last&.to_f
    refute_nil integrated, "ebur128 reported no integrated loudness for demo.mp3"

    target = eval_in_engine("puts JSON.generate(t: MASTER_LUFS_BY_STYLE[:default])").fetch("t")
    assert_in_delta target, integrated, 2.0,
                    "demo.mp3 integrated loudness #{integrated} LUFS is more than 2 LU " \
                    "from the #{target} LUFS target -- mastering did not run, or ran twice"
  end

  def test_master_heuristics_has_no_parallel_council
    result = eval_in_engine(<<~RUBY)
      puts JSON.generate(
        has_crit: DillaMaster.respond_to?(:crit_session_from_metrics),
        has_catalog: DillaMaster.const_defined?(:SOLUTION_CATALOG),
        has_phone: DillaMaster.respond_to?(:phone_preview_acceptable?)
      )
    RUBY
    refute result.fetch("has_crit"), "council must live in MASTER, not DillaMaster"
    refute result.fetch("has_catalog")
    assert result.fetch("has_phone")
  end

  def test_dmesg_openbsd_attach_style
    result = eval_in_engine(<<~RUBY)
      lines = []
      def capture_dmesg
        io = StringIO.new
        old = $stderr
        $stderr = io
        yield
        $stderr = old
        io.string.lines.map(&:chomp)
      end
      require "stringio"
      lines = capture_dmesg do
        DillaDmesg.boot!(mode: "dilla", cmd: "test")
        DillaDmesg.stream!(mode: "fast", bars: 32, order_n: 12)
        DillaDmesg.track!("quartal_west_coast", "pad=blend/wash lead=0")
        DillaDmesg.run!("ffmpeg -i x", exitstatus: 0, seconds: 1.2)
        DillaDmesg.write!("/tmp/demo.wav", bytes: 1024)
        DillaDmesg.warn("example warn")
      end
      puts JSON.generate(lines: lines)
    RUBY
    lines = result.fetch("lines")
    assert lines.any? { |l| l.match?(/\Adilla0 at mainbus0:/) }, lines.inspect
    assert lines.any? { |l| l.match?(/\Astream0 at dilla0:/) }, lines.inspect
    assert lines.any? { |l| l.match?(/\Atrack0 at stream0: quartal_west_coast/) }, lines.inspect
    assert lines.any? { |l| l.match?(/\Aexec0 at dilla0: run .*exit=0/) }, lines.inspect
    assert lines.any? { |l| l.match?(/\Aaudio0 at dilla0: write demo\.wav 1024b/) }, lines.inspect
    assert lines.any? { |l| l.match?(/\Awarn0 at dilla0: warn /) }, lines.inspect
    lines.each do |l|
      assert_equal l, l.downcase, "dmesg lines must be lowercase: #{l}"
    end
  end

  # Whole-pipeline smoke, and it runs by default.
  #
  # It was opt-in behind DILLA_SMOKE=1, which meant the suite passed having
  # rendered no audio at all: 87 tests green over an engine whose sound paths
  # were never executed. That is how a refactor gets called verified at the
  # method-and-constant level while a stage of the chain is silently gone, which
  # has happened here twice -- and MASTER's own autofix has broken this engine
  # past a check whose entire content was "does it parse".
  #
  # So it asserts three things a parse cannot: that the stages are in the log,
  # that there is sound, and that the sound is neither silence nor clipping.
  # Twenty seconds against a 30-second per-test budget; DILLA_SMOKE=0 skips it
  # on a machine without ffmpeg time to spare.
  def test_smoke_two_bar_render_runs_the_whole_chain_and_lands_in_range
    skip "DILLA_SMOKE=0 set" if ENV["DILLA_SMOKE"] == "0"
    skip "ffmpeg/ffprobe not available" unless system("which ffmpeg ffprobe > /dev/null 2>&1")

    Dir.mktmpdir do |dir|
      out = File.join(dir, "smoke.wav")
      stdout, err, status = Open3.capture3(
        { "DILLA_SCRATCH_DIR" => File.join(dir, "scratch"), "DILLA_OUTPUT_DIR" => dir, "BARS" => "2" },
        RbConfig.ruby, ENGINE, "dilla", out
      )
      assert status.success?, "2-bar render failed: #{err}"
      assert File.file?(out), "render reported success but wrote no file"
      log = stdout + err

      # Named stages, because "it produced a file" is true of a render with the
      # analog chain, the tape stage or the master bus missing entirely.
      {
        "harmony" => /harm|chord|progression/i,
        "drums" => /kick|drum/i,
        "the tape stage" => /tape:/i,
        "the master bus" => /master:.*lufs/i,
      }.each do |stage, pattern|
        assert_match pattern, log, "#{stage} left no trace in the render log"
      end

      duration, = Open3.capture3("ffprobe", "-v", "error", "-show_entries", "format=duration",
                                 "-of", "default=noprint_wrappers=1:nokey=1", out)
      assert_operator duration.to_f, :>, 1.0, "rendered file has no measurable duration"

      # Silence and clipping are the two ways a render can succeed and be
      # useless, and both have happened.
      _o, volume, = Open3.capture3("ffmpeg", "-hide_banner", "-nostats", "-i", out,
                                   "-af", "volumedetect", "-f", "null", "-")
      mean = volume[/mean_volume:\s*(-?[\d.]+) dB/, 1]&.to_f
      peak = volume[/max_volume:\s*(-?[\d.]+) dB/, 1]&.to_f
      refute_nil mean, "volumedetect printed no mean level: #{volume}"
      assert_operator mean, :>, -45.0, "the render is effectively silent (#{mean} dB mean)"
      assert_operator peak, :<, -0.1, "the render is clipping (#{peak} dB peak)"
    end
  end

  # rap_vocal_fold_bpm decides what tempo a vocal "is" before anything stretches
  # it, so a wrong answer here cannot be corrected downstream. Its pool used to
  # include b*1.5, b/1.5, b*4/3 and b*3/4 — factors that move where the beats
  # fall rather than just which octave you count them in. gunnhild measured
  # ~116, 116 * 3/4 = 87.0 landed inside the old 74-100 window and won for being
  # nearest 90, so every fit stretched a 120 BPM vocal as if it were 87.
  def test_bpm_folding_uses_octaves_only
    result = eval_in_engine(<<~RUBY)
      puts JSON.generate(
        from_116: rap_vocal_fold_bpm(116.0, target: 92.0),
        from_120: rap_vocal_fold_bpm(120.0, target: 92.0),
        from_45:  rap_vocal_fold_bpm(45.0,  target: 92.0),
        from_184: rap_vocal_fold_bpm(184.0, target: 92.0)
      )
    RUBY

    # Every answer must be the source tempo times a power of two.
    { "from_116" => 116.0, "from_120" => 120.0, "from_45" => 45.0, "from_184" => 184.0 }.each do |key, src|
      folded = result.fetch(key).to_f
      ratio = folded / src
      octaves = Math.log2(ratio)
      assert_in_delta octaves.round, octaves, 0.001,
                      "#{key}: #{src} -> #{folded} is not an octave fold (x#{ratio.round(3)})"
    end

    refute_equal 87.0, result.fetch("from_116").to_f,
                 "116 * 3/4 = 87 is the meter-shifting fold that mis-tempoed gunnhild"
  end

  # The aligner scores the vocal's own onsets, so it has to grid them at the
  # vocal's own bar length. It was passed the target tempo instead: at 87 source
  # against a 92 beat it compared onsets spaced 2.759s to a 2.609s grid, and the
  # offset it returned meant nothing.
  def test_bar_offset_grids_at_the_tempo_it_is_given
    result = eval_in_engine(<<~RUBY)
      # Onsets exactly one 120 BPM bar apart (2.0s), offset by 0.5s.
      phrases = (0..7).map { |i| { "start" => 0.5 + (i * 2.0) } }
      puts JSON.generate(
        at_120: rap_vocal_best_bar_offset("/dev/null", 120.0, phrases: phrases),
        at_92:  rap_vocal_best_bar_offset("/dev/null", 92.0, phrases: phrases)
      )
    RUBY

    # Given the right tempo it finds the phase; the bar repeats, so any whole
    # number of bars off 0.5 is the same answer.
    at_120 = result.fetch("at_120").to_f
    assert_in_delta 0.5, at_120 % 2.0, 0.05,
                    "should lock to the 0.5s phase of a 2.0s bar, got #{at_120}"

    refute_in_delta at_120, result.fetch("at_92").to_f, 0.001,
                    "gridding at the wrong tempo must not coincidentally agree"
  end

  # atempo preserves pitch, so nothing in the vocal path used to change a stem's
  # key and a vocal in the wrong key stayed there for the whole render.
  def test_progression_pitch_class_weights_cover_unregistered_voicings
    result = eval_in_engine(<<~RUBY)
      puts JSON.generate(
        db_major_minor_fall: progression_pitch_class_weights(:db_major_minor_fall),
        soul: progression_pitch_class_weights(:soul),
        lookup_hit: !PAD_CHORD_LOOKUP["Fm9"].nil?,
        lookup_miss: PAD_CHORD_LOOKUP["Fm7"].nil?
      )
    RUBY

    assert result.fetch("lookup_miss"),
           "test premise: Fm7 is not a registered pad voicing"
    assert result.fetch("lookup_hit"), "test premise: Fm9 is registered"

    # db_major_minor_fall is Dbmaj7 Cm7 Fm7 Bbm7 — every chord misses PAD_CHORD_LOOKUP,
    # which is exactly the case that scored as "no harmony at all" before the
    # root-parsing fallback.
    weights = result.fetch("db_major_minor_fall")
    refute_nil weights, "a progression of unregistered voicings must still yield weights"
    assert_equal 12, weights.length
    assert_in_delta 1.0, weights.sum, 0.001, "weights must be normalised"
    names = %w[C Db D Eb E F Gb G Ab A Bb B]
    # Db major / Bb minor: the roots Db, C, F and Bb must all carry weight, and
    # E — in none of the four chords — must carry none.
    %w[Db C F Bb].each do |pc|
      assert_operator weights[names.index(pc)], :>, 0.0,
                      "#{pc} is a chord root of db_major_minor_fall but scored zero"
    end
    assert_in_delta 0.0, weights[names.index("E")], 0.001,
                    "E is in no db_major_minor_fall chord and must not score"
  end

  def test_key_shift_prefers_smaller_moves_and_leaves_in_key_vocals_alone
    result = eval_in_engine(<<~RUBY)
      names = %w[C Db D Eb E F Gb G Ab A Bb B]
      weights = progression_pitch_class_weights(:db_major_minor_fall)
      # A chroma already sitting on the progression's strongest tones.
      in_key = Array.new(12, 0.0)
      %w[F C Db Ab].each { |n| in_key[names.index(n)] = 0.25 }
      # A chroma one semitone below those tones — a shift of +1 lands it home.
      one_below = Array.new(12, 0.0)
      %w[F C Db Ab].each { |n| one_below[(names.index(n) - 1) % 12] = 0.25 }
      # Two semitones below.
      two_below = Array.new(12, 0.0)
      %w[F C Db Ab].each { |n| two_below[(names.index(n) - 2) % 12] = 0.25 }
      puts JSON.generate(
        in_key: rap_vocal_key_shift(in_key, weights),
        one_below: rap_vocal_key_shift(one_below, weights),
        two_below: rap_vocal_key_shift(two_below, weights),
        flat_chroma: rap_vocal_key_shift(Array.new(12, 1.0 / 12), weights),
        no_progression: rap_vocal_key_shift(in_key, nil),
        max_shift: RAP_VOCAL_KEY_MAX_SHIFT
      )
    RUBY

    assert_equal 0, result.fetch("in_key"),
                 "a vocal already on the chord tones must not be transposed"
    assert_equal 1, result.fetch("one_below"),
                 "a vocal a semitone flat of the chord tones must come up one"
    assert_equal 2, result.fetch("two_below"),
                 "a whole tone is worth correcting when the evidence is unambiguous"
    assert_equal 0, result.fetch("flat_chroma"),
                 "a chroma with no pitch centre gives no shift any evidence"
    assert_equal 0, result.fetch("no_progression"),
                 "an unknown progression must not transpose anything"

    # Never exceed the formant budget, whatever the chroma says.
    assert_operator result.fetch("max_shift"), :<=, 2
  end

  # asetrate moves pitch and tempo together; without the atempo compensation the
  # transpose would also re-tempo the vocal off the beat it was just fitted to.
  def test_pitch_shift_chain_compensates_tempo_and_no_ops_at_zero
    result = eval_in_engine(<<~RUBY)
      puts JSON.generate(
        zero: rap_vocal_pitch_shift_chain(0).inspect,
        up1: rap_vocal_pitch_shift_chain(1),
        down2: rap_vocal_pitch_shift_chain(-2),
        sample_rate: SAMPLE_RATE
      )
    RUBY

    assert_equal "nil", result.fetch("zero"),
                 "no shift must add no filter, not a unity-ratio resample"

    sr = result.fetch("sample_rate").to_f
    up = result.fetch("up1")
    ratio = 2**(1 / 12.0)
    assert_includes up, "asetrate=#{(sr * ratio).round}"
    assert_includes up, "aresample=#{sr.to_i}"
    # atempo must undo exactly what asetrate did.
    tempos = up.scan(/atempo=([0-9.]+)/).flatten.map(&:to_f)
    refute_empty tempos, "pitch shift must compensate tempo"
    assert_in_delta 1.0 / ratio, tempos.reduce(1.0, :*), 0.0005,
                    "atempo product must invert the asetrate ratio"

    down = result.fetch("down2")
    down_ratio = 2**(-2 / 12.0)
    assert_includes down, "asetrate=#{(sr * down_ratio).round}"
    down_tempos = down.scan(/atempo=([0-9.]+)/).flatten.map(&:to_f)
    assert_in_delta 1.0 / down_ratio, down_tempos.reduce(1.0, :*), 0.0005
  end

  # bpm+bars named the same fit file for two tracks at the same tempo in
  # different keys, so the second silently reused a transpose built for the
  # first one's harmony.
  def test_fit_filename_encodes_the_key_shift
    result = eval_in_engine(<<~RUBY)
      puts JSON.generate(
        none: format("fit_%d_%dbars%s.wav", 86, 16, 0.zero? ? "" : format("_key%+d", 0)),
        up: format("fit_%d_%dbars%s.wav", 86, 16, format("_key%+d", 1)),
        down: format("fit_%d_%dbars%s.wav", 86, 16, format("_key%+d", -2))
      )
    RUBY

    assert_equal "fit_86_16bars.wav", result.fetch("none"),
                 "an untransposed fit keeps the historical filename"
    assert_equal "fit_86_16bars_key+1.wav", result.fetch("up")
    assert_equal "fit_86_16bars_key-2.wav", result.fetch("down")
    refute_equal result.fetch("up"), result.fetch("down")
  end

  # The .dilla manifest beside every render claims "Reproduce with: ...", so a
  # knob the scan misses is not a missing line in a report — it is a recipe that
  # silently omits an ingredient. The scan globbed lib/*.rb, one level, and the
  # engine split into lib/engine/ dropped 484 of 610 knobs without failing
  # anything. Named knobs here rather than a bare count: a count can be met by
  # any 610 strings, and these six are the ones the module's own comment records
  # as having gone missing the first time.
  def test_provenance_records_the_knobs_the_engine_reads_from_every_engine_file
    require File.expand_path("../dilla/lib/provenance", __dir__)
    keys = DillaProvenance.engine_env_keys

    %w[PROGRESSION SONITEX RAP_VOCAL ANALOG_CHAIN PAD_VOL KICK_GAIN].each do |knob|
      assert_includes keys, knob,
                      "#{knob} decides how a render sounds, so a manifest without it cannot rebuild one"
    end
    assert_operator keys.length, :>=, 600,
                    "the engine reads 610 knobs; a sharp drop means the source glob stopped seeing files"
  end

  # Five places each answered "which files is the engine made of" separately, and
  # they disagreed: the parse check ran over 80 files while the engine was 116,
  # so all thirty lib/*.rb modules were never syntax-checked at all -- and that is
  # the check MASTER's autofix has broken this engine past before. The fix is
  # DillaSources; this test is what stops a sixth answer appearing.
  def test_engine_sources_is_the_only_definition_of_what_the_engine_is
    require File.expand_path("../dilla/lib/engine_sources", __dir__)
    root = DillaSources.root

    assert_empty Dir[File.join(root, "lib", "engine", "*.rb")],
                 "lib/engine/ is back -- the engine is one file, and a part there is required by nothing"
    on_disk = Dir[File.join(root, "lib", "*.rb")].length + 1
    assert_equal on_disk, DillaSources.all.length,
                 "DillaSources.all must be every ruby file the engine is made of, or the checks that read it are partial"

    # A re-derivation is a glob over the engine's own source directories. Comment
    # bodies are excluded the same way the wiring ratchets exclude them: this rule
    # is quoted in prose in engine_sources.rb itself, which is the file allowed to
    # own the answer.
    reglob = /Dir(?:\.glob)?[\[(][^)\]]*(?:"|')[^"']*lib[^"']*(?:engine|\*\*|\*\.rb)/
    offenders = DillaSources.all.reject { |p| File.basename(p) == "engine_sources.rb" }.filter_map do |path|
      body = File.read(path).gsub(/^\s*#(?!\{).*$/, "")
      "#{File.basename(path)}: #{body[reglob]}" if body.match?(reglob)
    end
    assert_empty offenders,
                 "these re-derive the engine's file list instead of reading DillaSources — the drift that cost " \
                 "484 of 610 provenance knobs started exactly here"
  end

  # The registry is derived from the source rather than declared beside it, for
  # the reason provenance.rb's own comment gives. What it says about a knob is
  # therefore only worth what the extractor is worth, so this pins the extractor
  # against knobs whose behaviour is documented in the engine's own comments --
  # including the two it got wrong on the first attempt, both in the direction of
  # telling the operator a working value was a mistake.
  def test_knob_registry_reads_each_knob_as_the_engine_reads_it
    require File.expand_path("../dilla/lib/knobs", __dir__)

    assert_operator DillaKnobs.all.length, :>=, 600, "the engine reads 610 knobs"

    # A path with an off-switch is a path. Calling SAMPLE_LOOP a flag is the
    # mistake that cost thirteen renders their sample bed.
    assert_equal :path, DillaKnobs["SAMPLE_LOOP"].type
    # ...and its off-switch is a %w[] constant declared above the check, so a
    # scanner reading only inline literals would call the working SAMPLE_LOOP=1
    # an error.
    assert_includes DillaKnobs["SAMPLE_LOOP"].accepted, "1"

    # EXTERNAL_KIT names a kit that the code joins onto a cache directory. It is
    # not a path, and reporting it as a missing file flagged the engine's own
    # default on a clean environment.
    assert_equal :string, DillaKnobs["EXTERNAL_KIT"].type

    # A flag is boolean. PAD_VOICE is compared against "0" somewhere and picks a
    # synth voice by name everywhere else.
    assert_equal :string, DillaKnobs["PAD_VOICE"].type

    assert_equal 0.08..1.35, DillaKnobs["KICK_GAIN"].range
    assert_equal :float, DillaKnobs["KICK_GAIN"].type
    assert_equal "0.62", DillaKnobs["DILLA_XCONV_WET"].default
  end

  def test_knob_check_finds_real_mistakes_and_stays_quiet_otherwise
    require File.expand_path("../dilla/lib/knobs", __dir__)

    # Each of these is a mistake the engine used to accept in silence.
    problems = DillaKnobs.validate(
      "SONITEXT" => "heavy",              # typo: nothing reads it
      "PAD_TEXTURE" => "true",            # compared against "1" only, so this is OFF
      "DILLA_QUALITY_GATE" => "false",    # compared against "0" only, so this is ON
      "SAMPLE_EXCITE" => "3.0",           # clamped to 0..1
      "SAMPLE_LOOP" => "/nope.wav",       # a path to nothing
      "DILLA_RENDER_SEED" => "12345"      # an output of a render, not an input
    )
    %w[SONITEXT PAD_TEXTURE DILLA_QUALITY_GATE SAMPLE_EXCITE SAMPLE_LOOP DILLA_RENDER_SEED].each do |knob|
      assert(problems.any? { |p| p.start_with?(knob) }, "#{knob} should have been reported; got #{problems.inspect}")
    end
    assert_match(/did you mean SONITEX\?/, problems.find { |p| p.start_with?("SONITEXT") })

    # And values that are right must be silent, or the report gets skipped. This
    # ran at 62 notes for a correct environment before the ==/!= distinction went
    # in, of which four were real.
    assert_empty DillaKnobs.validate(
      "SONITEX" => "heavy", "PAD_TEXTURE" => "1", "SAMPLE_EXCITE" => "0.3",
      "KICK_GAIN" => "0.9", "FM_DRUMS" => "0", "SPECTRAL_ARP" => "0", "BPM" => "96"
    )
  end

  # RELEASE.mp3's sidecar recorded 171 knobs and could not rebuild the file.
  # Replaying every recorded value converts engine-chosen defaults into operator
  # pins, which locks out the tables that chose them -- so the recipe is not the
  # environment, it is the part of it the caller typed.
  def test_provenance_separates_what_the_operator_pinned_from_what_the_engine_filled
    require File.expand_path("../dilla/lib/provenance", __dir__)

    Dir.mktmpdir do |dir|
      output = File.join(dir, "pins.wav")
      env = { "BARS" => "2", "SONITEX" => "heavy", "PAD_VOL" => "60", "DILLA_OUTPUT_DIR" => dir }
      env["DILLA_SCRATCH_DIR"] = File.join(dir, "scratch")
      _out, err, status = Open3.capture3(env, RbConfig.ruby, ENGINE, "dilla", output)
      assert status.success?, "the render must succeed before its manifest means anything: #{err}"

      manifest = JSON.parse(File.read("#{output}.dilla"))
      pinned = manifest.fetch("pinned")
      assert_equal({ "BARS" => "2", "SONITEX" => "heavy", "PAD_VOL" => "60",
                     "DILLA_OUTPUT_DIR" => dir, "DILLA_SCRATCH_DIR" => File.join(dir, "scratch") }, pinned,
                   "pinned is what the caller typed — no more, and the toolchain's own variables are not knobs")
      assert_operator manifest.fetch("environment").length, :>, pinned.length,
                      "environment still records everything, for reading rather than for replaying"

      # DILLA_RENDER_SEED is written by drum_kit.rb from the seed above it.
      # Feeding it back in as an input is feeding a result back in as a cause.
      refute manifest.fetch("environment").key?("DILLA_RENDER_SEED")
      assert manifest.fetch("derived").key?("DILLA_RENDER_SEED")

      assert_match(/RENDER_SEED=\d+ .*SONITEX=heavy.*ruby dilla\.rb/, manifest.fetch("note"),
                   "the sentence that claims reproduction has to carry the pins")
    end
  end

  # A pre/post comparison of a refactor was abandoned because session.json moved
  # between the two takes, so the refactor shipped unmeasured. Frozen reads the
  # learned state and writes none of it, which is what makes an A/B possible at
  # all -- and it has to be provable in both directions, or "frozen" is a claim
  # rather than a behaviour.
  def test_dilla_frozen_reads_the_learned_state_and_writes_none_of_it
    session = File.expand_path("../dilla/project/session.json", __dir__)
    skip "no session state on this machine yet" unless File.file?(session)

    # One render, not two: the suite gives each test 30 seconds and a render is
    # about twenty, so the unfrozen control lives in the test below where it
    # costs nothing. What this proves is that a whole real render, with every
    # writer the engine reaches, leaves the state where it found it.
    Dir.mktmpdir do |dir|
      env = { "BARS" => "2", "DILLA_FROZEN" => "1",
              "DILLA_SCRATCH_DIR" => File.join(dir, "scratch"), "DILLA_OUTPUT_DIR" => dir }
      # Content, not mtime.
      #
      # This asked for mtime and failed about one run in four, on an engine that
      # is not at fault: twenty consecutive frozen renders were measured against
      # this file and moved neither its bytes nor its timestamp. What moved the
      # mtime was the suite's own duplicate restore hook, writing byte-identical
      # content back -- see the note at the top of this file.
      #
      # Content is also the stricter question, which is why this is not a test
      # being relaxed to make it pass. The paragraph above says what frozen is
      # for: an A/B whose two takes differ because of the change and not because
      # the state moved between them. What breaks that is the state's CONTENT
      # changing. A timestamp that moves while the bytes stand still breaks
      # nothing, and a byte that changes while the timestamp somehow holds would
      # break everything and pass the old assertion.
      before = File.binread(session)
      _o, err, status = Open3.capture3(env, RbConfig.ruby, ENGINE, "dilla", File.join(dir, "cold.wav"))
      assert status.success?, "frozen render failed: #{err}"

      assert_equal before, File.binread(session), "DILLA_FROZEN=1 must not write the session back"
      assert_match(/frozen: not writing project\/session\.json/, err,
                   "a skipped write is announced; silently dropping data would be worse than the bug this fixes")
      assert_includes JSON.parse(File.read(File.join(dir, "cold.wav.dilla"))).fetch("frozen"),
                      "project/session.json",
                      "the manifest has to say the take was made against held state"
    end
  end

  # How much of the shared spine each renderer reaches, as a ratchet.
  #
  # The existing spine test asks whether the techno renderer CAN reach harmony.
  # This asks how much of it every renderer reaches, and refuses to let any of
  # them reach less than they do today. Genre is meant to be a parameter, and
  # the way it stops being one is a renderer quietly growing its own copy of
  # something the spine already does.
  #
  # Transitively, one level of calls deep, which matters: measured on each
  # method's own body, render_hate_techno reads as not reaching the sampled bed,
  # and it does reach it — through techno_bed_part!. A reach measurement that
  # only reads the entry method reports forks that are not there, and this one
  # did before it followed calls.
  #
  # The baseline is what is true today, not what should be. Two renderers do not
  # reach the bed and three do not reach the arrangement, and in the techno
  # renderer's case that is because it HAS an arrangement — hate_gate, a second
  # implementation of section_layer_windows in a different vocabulary. Merging
  # them changes how every techno set sounds, so it stays the operator's call;
  # what this stops is the number going the other way.
  GENRE_SPINE_BASELINE = {
    "render_dilla" => %w[harmony bed groove arrangement],
    "render_hate_techno" => %w[harmony bed groove],
    "render_industrial" => %w[harmony groove],
    "render_analog" => %w[harmony groove],
  }.freeze

  def test_genre_renderers_reach_of_the_shared_spine_never_narrows
    result = eval_in_engine(<<~RUBY)
      src = engine_source
      index = []
      src.enum_for(:scan, /\\ndef ([a-z_][\\w?!]*)/).each { index << [Regexp.last_match.begin(0), $1] }
      bodies = {}
      index.each_with_index do |(pos, name), i|
        # Comments stripped, the same rule the wiring ratchets use and for the
        # same reason. A comment ABOUT the shared arrangement is where this
        # duplication is documented, and matching it reported hate_gate as
        # reaching the thing it is a second copy of.
        body = src[pos, (index[i + 1]&.first || src.length) - pos]
        bodies[name] ||= body.gsub(/^\\s*#(?!\\{).*$/, "")
      end

      markers = { "harmony" => /dilla_progression|techno_harmony_roots|generate_progression|voice_lead_chords/,
                  "bed" => /sample_loop_for|build_sample_loop_filter|_bed_part!/,
                  "groove" => /dilla_schedule|pocket|swing|groove/,
                  "arrangement" => /apply_section_envelope|dilla_section|section_layer/ }

      reach = lambda do |name, seen, depth|
        return {} if depth > 3 || seen[name] || bodies[name].nil?
        seen[name] = true
        body = bodies[name]
        found = markers.transform_values { |re| !!(body =~ re) }
        body.scan(/\\b([a-z_][\\w]*[!?]?)\\s*\\(/).flatten.uniq.each do |callee|
          next unless bodies.key?(callee)
          reach.call(callee, seen, depth + 1).each { |k, v| found[k] ||= v }
        end
        found
      end

      out = {}
      #{GENRE_SPINE_BASELINE.keys.inspect}.each do |m|
        r = reach.call(m, {}, 0)
        out[m] = r.select { |_, v| v }.keys.sort
      end
      puts JSON.generate(out)
    RUBY

    GENRE_SPINE_BASELINE.each do |renderer, expected|
      actual = result.fetch(renderer, [])
      missing = expected - actual
      assert_empty missing,
                   "#{renderer} stopped reaching #{missing.join(', ')} — genre is a parameter only while the " \
                   "renderers share the spine, and this is how that quietly stops being true"
      gained = actual - expected
      next if gained.empty?

      # Not a failure. A renderer reaching MORE is the direction this wants; the
      # baseline has to be updated so the ratchet holds at the new level.
      puts "NOTE   #{renderer} now also reaches #{gained.join(', ')} — raise GENRE_SPINE_BASELINE"
    end
  end

  # I cannot hear these renders, so every measurement I take of them is worth
  # exactly what its instrument is worth. This tool reports which dimensions
  # separate the operator's kept takes from their rejected ones, and it got the
  # first one wrong: ebur128 prints a running I: per frame and the summary last,
  # so reading the FIRST match gave -70 LUFS for everything and two piles 14 dB
  # apart reported no separation in loudness. It was caught only by running it
  # against a difference that was known in advance, which is what this test is.
  def test_taste_separates_two_piles_on_a_difference_it_was_given
    skip "ffmpeg not available" unless system("which ffmpeg > /dev/null 2>&1")
    require File.expand_path("../dilla/lib/taste", __dir__)

    Dir.mktmpdir do |dir|
      # The piles differ in level and in nothing else.
      kept, rejected = [-6, -20].map do |db|
        (1..3).map do |i|
          path = File.join(dir, "#{db}_#{i}.wav")
          system("ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i",
                 "sine=frequency=#{200 + i * 40}:duration=4",
                 "-af", "volume=#{db}dB", "-ac", "2", path, exception: true)
          path
        end
      end

      result = DillaTaste.compare(kept, rejected)
      findings = result.fetch(:findings).to_h { |f| [f[:dimension], f] }

      loudness = findings.fetch("integrated loudness")
      assert_operator loudness[:separation], :>, 1.5,
                      "a 14 dB level difference must separate on loudness; it read 0.00 before the summary-line fix"
      assert_operator loudness[:kept][:mean], :>, loudness[:rejected][:mean]
      assert_in_delta 14.0, loudness[:kept][:mean] - loudness[:rejected][:mean], 1.5,
                      "and it must separate by roughly the amount it was given, not merely in the right direction"

      # Just as important: the dimensions that did NOT differ must report that
      # they did not. A tool that finds something in every dimension finds
      # nothing, and would tune this engine against noise.
      %w[transient density low-versus-mid balance stereo width].each do |quiet|
        next unless findings.key?(quiet)

        assert_operator findings[quiet][:separation], :<, 1.5,
                        "#{quiet} is identical in both piles and must not be reported as a difference"
      end

      assert_equal({ error: "need at least two files on each side" }, DillaTaste.compare(kept.first(1), rejected),
                   "one take a side is an anecdote, and the tool has to say so rather than compute a spread of zero")
    end
  end

  # SECTION_LAYER_GAIN said the lead is silent through the intro, the breakdown,
  # the build and the outro, and the chops through three of them. Nothing ever
  # called apply_section_envelope for either, so the most dramatic instruction in
  # the arrangement -- on the layer a listener notices first -- was a hash entry
  # with no reader. Meanwhile :harm WAS applied and was not in the table, so that
  # call returned the chain untouched every time it ran. Neither failed anything.
  #
  # This is the diff that would have said so.
  def test_every_declared_section_layer_is_wired_and_every_wired_one_declared
    result = eval_in_engine(<<~RUBY)
      applied = SECTION_LAYERS_APPLIED.map(&:to_s)
      puts JSON.generate(
        declared: SECTION_LAYERS_DECLARED.map(&:to_s).sort,
        applied: applied.sort,
        lead_windows: section_layer_windows(:lead, 16, 2.0),
        harm_windows: section_layer_windows(:harm, 16, 2.0)
      )
    RUBY

    assert_equal result.fetch("declared"), result.fetch("applied"),
                 "a layer with a gain nobody reads is not an arrangement, and a layer read with no gain is a no-op"

    # The lead's declared silences are real windows, not an empty list.
    refute_empty result.fetch("lead_windows"),
                 "the lead has sections it is supposed to sit out; if this is empty the table stopped saying so"
    assert(result.fetch("lead_windows").any? { |_from, _to, gain| gain.zero? },
           "silent means gain 0 somewhere")

    # :harm is declared at full level everywhere on purpose — see the comment on
    # SECTION_LAYER_GAIN. Giving the pads a shape is the operator's call; this
    # only proves the wiring is no longer pointed at nothing.
    assert(result.fetch("harm_windows").all? { |_from, _to, gain| gain == 1.0 },
           "declaring :harm must not change what the pads do")
  end

  # Working out what is in RELEASE.mp3 took envelope-fingerprinting every audio
  # file still on disk against the master, because a 44-minute compilation's
  # only record was a sidecar describing one 160-second render. An assembly has
  # to write down its parts, and it has to inline each part's recipe rather than
  # point at it: renders are gitignored and the seed rotates, so a manifest
  # referring to a deleted wav records nothing at all.
  def test_an_assembly_records_its_parts_with_offsets_and_their_recipes
    require File.expand_path("../dilla/lib/provenance", __dir__)

    Dir.mktmpdir do |dir|
      parts = %w[a b].map { |name| File.join(dir, "#{name}.wav") }
      parts.each_with_index do |part, index|
        # 0.4s of tone is enough to have a duration and a hash; this test is
        # about the bookkeeping, and a real render costs twenty seconds.
        system("ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i",
               "sine=frequency=#{220 * (index + 1)}:duration=0.4", "-ac", "2", part, exception: true)
        File.write("#{part}.dilla", JSON.generate(
                                      "render_seed" => 100 + index,
                                      "pinned" => { "BARS" => "2" },
                                      "note" => "Reproduce with: ...",
                                      "engine" => { "commit" => "abc123" }
                                    ))
      end

      DillaProvenance.instance_variable_set(:@root, dir)
      joined = File.join(dir, "master.wav")
      FileUtils.cp(parts.first, joined)
      DillaProvenance.record_assembly!(joined, parts:, how: "test join")

      assembly = JSON.parse(File.read("#{joined}.dilla")).fetch("assembly")
      assert_equal 2, assembly.fetch("parts")
      assert_equal "test join", assembly.fetch("how")

      first, second = assembly.fetch("from")
      assert_equal "a.wav", first.fetch("path")
      assert_in_delta 0.0, first.fetch("starts_at"), 0.001
      assert_in_delta first.fetch("seconds"), second.fetch("starts_at"), 0.01,
                      "part 2 starts where part 1 ends — an offset is what makes this a tracklist"
      assert_equal 64, first.fetch("sha256").length

      # The part's recipe, copied in. This is the whole point: it has to survive
      # the part being deleted.
      assert_equal 101, second.dig("recipe", "render_seed")
      assert_equal({ "BARS" => "2" }, second.dig("recipe", "pinned"))
      parts.each { |part| FileUtils.rm_f([part, "#{part}.dilla"]) } # scan: intentional — removes only the temp files this method rendered
      assert_equal 101, JSON.parse(File.read("#{joined}.dilla")).dig("assembly", "from", 1, "recipe", "render_seed"),
                   "the record still names what part 2 was made from after part 2 is gone"
    end
  end

  # The control for the test above, and the mechanism on its own: frozen has to
  # be the only difference, or "it did not write" proves nothing about freezing.
  def test_frozen_state_writes_when_thawed_and_announces_every_skip
    require File.expand_path("../dilla/lib/frozen_state", __dir__)

    Dir.mktmpdir do |dir|
      target = File.join(dir, "state.json")
      DillaFrozen.reset!

      ENV.delete("DILLA_FROZEN")
      assert DillaFrozen.write_json(target, { "generation" => 1 }), "thawed must report that it wrote"
      assert_equal 1, JSON.parse(File.read(target)).fetch("generation")

      ENV["DILLA_FROZEN"] = "1"
      captured = capture_io { refute DillaFrozen.write_json(target, { "generation" => 2 }) }
      assert_equal 1, JSON.parse(File.read(target)).fetch("generation"), "frozen left the old value"
      assert_includes DillaFrozen.skips.join, "state.json"
      assert_match(/frozen: not writing/, captured.join)
    ensure
      ENV.delete("DILLA_FROZEN")
      DillaFrozen.reset!
    end
  end

  # The old meter split at 3.5 kHz, so 2–4 kHz sat inside mid and cancelled.
  # A synthetic mix that is quiet above 3.5 kHz and hot at 2–4 kHz must now
  # read as harsh; the same numbers on the old two-band shape must not, so a
  # caller that has not been updated keeps its previous result.
  def test_analyze_harshness_sees_the_presence_band
    require File.expand_path("../dilla/lib/master_heuristics", __dir__)

    old_shape = { mid: -18.0, high: -42.5 }
    old = DillaMaster.analyze_harshness(old_shape)
    refute old[:needs_notch], "two-band fallback must not invent a presence problem"
    assert_in_delta(-24.5, old[:harshness], 0.01)

    three = DillaMaster.analyze_harshness(
      mid: -18.0, high: -42.5, body: -20.0, presence: -13.5, air: -28.0
    )
    assert_in_delta(6.5, three[:harshness], 0.01)
    assert three[:needs_notch], "presence 6.5 dB above the body is the roughness the old meter missed"
    assert_in_delta(-13.5, three[:presence_db], 0.01)
    assert_in_delta(-20.0, three[:body_db], 0.01)
  end

  def test_loss_gates_reject_true_peak_and_lufs_and_share_the_quality_window
    require File.expand_path("../dilla/lib/master_heuristics", __dir__)

    gates = DillaMaster.loss_gates
    assert gates["true_peak_max_dbtp"], "loss_gates must name a true-peak ceiling"
    assert gates["integrated_lufs_min"], "loss_gates must name a LUFS floor"
    assert gates["integrated_lufs_max"], "loss_gates must name a LUFS ceiling"

    hot = DillaMaster.passes_loss_gates?({ true_peak_dbtp: 0.2, integrated_lufs: -8.0 })
    refute hot[:pass]
    assert(hot[:failures].any? { |line| line.include?("true_peak") }, hot[:failures].inspect)
    assert(hot[:failures].any? { |line| line.include?("integrated_lufs") }, hot[:failures].inspect)

    ok = DillaMaster.passes_loss_gates?({ true_peak_dbtp: -1.5, integrated_lufs: -17.0 })
    refute(ok[:failures].any? { |line| line.include?("true_peak") || line.include?("integrated_lufs") },
           ok[:failures].inspect)
  end

  def test_loss_gates_lufs_window_matches_the_quality_target
    result = eval_in_engine(<<~RUBY)
      require "yaml"
      gates = YAML.safe_load_file(DillaMaster::REFERENCE_PATH)["loss_gates"]
      puts JSON.generate(
        min: gates.fetch("integrated_lufs_min"),
        max: gates.fetch("integrated_lufs_max"),
        quality_min: DILLA_QUALITY_LUFS_TARGET.begin,
        quality_max: DILLA_QUALITY_LUFS_TARGET.end
      )
    RUBY
    assert_in_delta result.fetch("quality_min"), result.fetch("min"), 0.01,
                    "loss_gates LUFS floor must be DILLA_QUALITY_LUFS_TARGET.begin, not a second number"
    assert_in_delta result.fetch("quality_max"), result.fetch("max"), 0.01,
                    "loss_gates LUFS ceiling must be DILLA_QUALITY_LUFS_TARGET.end, not a second number"
  end

  def test_asoftclip_filter_strings_carry_oversample
    result = eval_in_engine(<<~RUBY)
      misses = ENGINE_SOURCES.flat_map do |path|
        File.read(path).each_line.with_index(1).filter_map do |line, number|
          next if line.lstrip.start_with?("#")
          next unless line.include?("asoftclip=type=")
          next if line.include?("oversample=")

          "\#{File.basename(path)}:\#{number}"
        end
      end
      puts JSON.generate(misses)
    RUBY
    assert_empty result, "asoftclip without oversample aliases above Nyquist"
  end

  def test_sample_modern_chain_is_called_from_the_loop_filter
    result = eval_in_engine(<<~RUBY)
      body = File.read(File.join(ROOT, "dilla.rb")).gsub(/^\\s*#(?!\\{).*$/, "")
      puts JSON.generate(called: body.include?("sample_modern_chain"))
    RUBY
    assert result.fetch("called"), "sample_modern_chain must run on the sample loop bus"
  end

  def test_melodic_lead_is_the_default_counter_line
    result = eval_in_engine(<<~RUBY)
      apply_dilla_style!(force: true)
      puts JSON.generate(
        melodic: ENV["MELODIC_LEAD"],
        arp: ENV["LEAD_ARP"],
        true_arp: lead_true_arp_mode?
      )
    RUBY
    assert_equal "1", result.fetch("melodic")
    # The signature lead layers an arp locked to the progression scale over the
    # counter-line, so LEAD_ARP defaults on. CREATIVE_LEAD stays off, which is
    # what keeps it following the harmony rather than improvising against it --
    # so true_arp is still false and the counter-line is still the subject here.
    assert_equal "1", result.fetch("arp")
    refute result.fetch("true_arp"), "default DNA is a counter-line, not subdiv arps"
  end

  def test_drum_vol_pin_moves_the_main_mix_weight
    result = eval_in_engine(<<~RUBY, env: { "DRUM_VOL" => "0.55" })
      puts JSON.generate(weight: resolved_drum_mix_weight, pinned: USER_PINNED_ENV["DRUM_VOL"])
    RUBY
    assert_equal "0.55", result.fetch("pinned")
    assert_in_delta 0.55, result.fetch("weight"), 0.001
  end

  def test_stream_rotation_keeps_operator_lead_pins
    result = eval_in_engine(<<~RUBY, env: { "LEAD_ARP" => "0", "HARMONY_LEAD" => "0" })
      ENV["STREAM_ROTATE_LEAD"] = "1"
      stream_rotate_voices_and_arps!(0)
      puts JSON.generate(arp: ENV["LEAD_ARP"], harmony: ENV["HARMONY_LEAD"])
    RUBY
    assert_equal "0", result.fetch("arp")
    assert_equal "0", result.fetch("harmony")
  end

  def test_wiring_dead_methods_do_not_rise
    result = eval_in_engine(<<~RUBY)
      dead = wiring_dead_methods
      puts JSON.generate(orphans: dead.keys.sort, n: dead.length, baseline: WIRING_DEAD_METHOD_BASELINE)
    RUBY
    assert_operator result.fetch("n"), :<=, result.fetch("baseline"),
                    "uncalled methods rose: #{result.fetch('orphans').inspect}"
  end
end
