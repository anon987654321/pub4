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
        bad_aliases: COMMAND_ALIASES.reject { |_, target| DISPATCH.key?(target) }.keys
      )
    RUBY
    expected = (result.fetch("dispatch_keys") + %w[midi beat]).sort
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
    assert_equal 3, result.fetch("lead_subdiv")
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
