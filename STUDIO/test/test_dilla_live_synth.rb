# frozen_string_literal: true

require_relative "dilla_helper"
require_relative "../dilla/lib/livesets"
require "stringio"
require "digest"

# The live synthesiser without a sound card: the ladder, the Model D panels,
# the harmony walk, the knobs, the sentences, and a few seconds of each mode
# rendered into memory.
class TestDillaLiveSynth < Minitest::Test
  RATE = 32_000

  def with_live_dir
    Dir.mktmpdir do |dir|
      saved = ENV.fetch("DILLA_LIVE_DIR", nil)
      ENV["DILLA_LIVE_DIR"] = dir
      yield dir
    ensure
      ENV["DILLA_LIVE_DIR"] = saved
    end
  end

  # Unclaimed players are reaped together with their audio children, their
  # terminal spared; a process that merely runs ffmpeg on its own is not.
  def test_orphan_stop_reaps_unclaimed_players_and_their_audio_children
    ps = <<~PS
      4602 999 3001 /Users/mac/Documents/GitHub/pub4/STUDIO/dilla/dilla.rb live standard
      4647 4602 91 /bin/bash -c ffmpeg
      4648 4647 91 /opt/homebrew/bin/ffmpeg -f s16le
      4649 4647 91 /opt/homebrew/bin/sox -t raw
      22968 999 91 -zsh
    PS
    terminated = nil
    status = Struct.new(:success?).new(true)

    Open3.stub(:capture2, [ps, status]) do
      LiveSynth::Session.stub(:terminate_processes, ->(pids) { terminated = pids }) do
        result = LiveSynth::Session.stop_orphans
        assert_equal "stopped 1 orphaned Dilla player", result
      end
    end

    assert_equal [4649, 4648, 4647, 4602], terminated
  end

  # The set the fold retired no longer names a target: an old liveset.rb
  # process, if one lingers, is nobody the orphan scan claims.
  def test_orphan_scan_spares_the_retired_liveset_process
    ps = <<~PS
      4602 999 3001 /Users/mac/Documents/GitHub/pub4/STUDIO/dilla/liveset.rb
      4649 4602 91 /opt/homebrew/bin/sox -t raw
    PS
    status = Struct.new(:success?).new(true)

    Open3.stub(:capture2, [ps, status]) do
      assert_equal "nothing is playing", LiveSynth::Session.stop_orphans
    end
  end

  # Played quietly into a StringIO: the samples a sink would have received.
  def perform(score, seconds:)
    stage = LiveSynth::Stage.new(rate: RATE, rng: score.rng)
    sink = StringIO.new(+"")
    out = $stdout
    $stdout = StringIO.new
    stage.run(score, sink, seconds:)
    sink.string.unpack("s<*")
  ensure
    $stdout = out
  end

  # Emphasis 10 with every mixer source at 10 and the output fed back: the
  # loudest, most resonant thing the panel can ask of the ladder.
  def test_the_ladder_stays_finite_and_bounded_at_full_emphasis_and_overdrive
    ladder = AnalogSynth::Ladder.new(rate: RATE)
    resonance = AnalogSynth::ModelD::EMPHASIS_FULL
    drive = 3 * AnalogSynth::ModelD::MIXER_FULL
    peak = 0.0
    (RATE * 2).times do |i|
      input = AnalogSynth.wave(:saw, (i * 55.0 / RATE) % 1.0) * drive
      out = ladder.process(input, 400.0 + (300.0 * Math.sin(i / 3000.0)), resonance)
      assert out.finite?, "sample #{i} is #{out}"
      peak = [peak, out.abs].max
    end
    assert_operator peak, :<=, 1.0, "four one-poles behind a tanh cannot leave the unit interval"
    assert_operator peak, :>, 0.05, "and at full emphasis they still sound"
  end

  # With no input at all, emphasis 10 rings on its own once anything nudges
  # the ladder -- the Model D's top of the dial -- and emphasis 8 does not.
  # Through 2 kHz: at 32 kHz a cutoff near 5 kHz puts the loop's phase point
  # so close to Nyquist that no resonance makes it ring.
  def test_emphasis_ten_self_oscillates_at_every_cutoff
    ring = lambda do |dial, hz|
      resonance = AnalogSynth::ModelD.dial(dial) * AnalogSynth::ModelD::EMPHASIS_FULL *
                  AnalogSynth::ModelD.self_oscillation(hz, RATE)
      ladder = AnalogSynth::Ladder.new(rate: RATE)
      ladder.process(0.5, hz, resonance)
      Array.new(RATE * 2) { ladder.process(0.0, hz, resonance) }.last(RATE / 4).map(&:abs).max
    end
    [100.0, 400.0, 800.0, 2_000.0].each do |hz|
      assert_operator ring.call(10, hz), :>, 1e-3, "emphasis 10 at #{hz} Hz"
      assert_operator ring.call(8, hz), :<, 1e-6, "emphasis 8 at #{hz} Hz"
    end
  end

  def test_every_model_d_panel_builds
    AnalogSynth::ModelD.names.each do |name|
      patch = AnalogSynth::ModelD.patch(name)
      assert patch[:model_d], name
      assert_equal patch[:waves].size, patch[:levels].size, name
      assert patch[:levels].all?(&:positive?), "#{name}: a source off in the mixer is left out"
      assert_kind_of AnalogSynth::Envelope, patch[:amp]
    end
  end

  # Footages are octaves from 8', so the fat bass sits two octaves and one
  # octave down; OSC 3 in LO is a free-running sweep, not a pitch.
  def test_panel_units_map_to_the_instrument
    bass = AnalogSynth::ModelD.patch("fat_bass")
    assert_equal [-2.0, -1.0, -1.0], bass[:octaves]
    assert_in_delta 523.25 / 8, bass[:cutoff], 0.01
    lead = AnalogSynth::ModelD.patch("minimoog_lead")
    assert_equal 2, lead[:waves].size, "OSC 3 is the vibrato, off in the mixer"
    assert_in_delta 2.0 * (2.0**1.5), lead[:mod][:hz], 1e-9
    assert lead[:glide].positive?
  end

  # One decay switch for both contours: on, release is the decay; off, a
  # released key stops at once.
  def test_the_decay_switch_sets_both_releases
    on = AnalogSynth::ModelD.patch("moog_pluck")
    assert_equal on[:amp].decay, on[:amp].release
    assert_equal on[:filter_env].decay, on[:filter_env].release
    off = AnalogSynth::ModelD.patch("fat_bass")
    assert_equal AnalogSynth::ModelD::SWITCH_OFF_RELEASE, off[:amp].release
  end

  def test_contour_dials_are_logarithmic_across_their_range
    assert_in_delta 0.001, AnalogSynth::ModelD.taper(0, AnalogSynth::ModelD::ATTACK_RANGE), 1e-12
    assert_in_delta 10.0, AnalogSynth::ModelD.taper(10, AnalogSynth::ModelD::ATTACK_RANGE), 1e-9
    assert_in_delta 0.1, AnalogSynth::ModelD.taper(5, AnalogSynth::ModelD::ATTACK_RANGE), 1e-9
  end

  # Each voice moves to the nearest tone of the next chord.
  def test_nearest_voicing_moves_each_voice_the_least
    previous = [55, 60, 63, 67, 70]
    fm9 = DillaImprovisation.pitch_classes(5, 0, "m9")
    voiced = DillaImprovisation.nearest_voicing(fm9, previous, range: 48..76, first: previous)
    assert_equal fm9.sort, voiced.map { |m| m % 12 }.sort
    assert voiced.all? { |m| (48..76).cover?(m) }
    voiced.each do |m|
      nearest = previous.map { |p| (m - p).abs }.min
      assert_operator nearest, :<=, 6, "#{m} is a tritone or less from a voice it came from"
    end
  end

  def test_the_walk_never_leaves_its_table
    moves = LiveSynth.config.dig("improvise", "moves").to_h { |row| [row["from"], row["to"]] }
    rng = Random.new(3)
    state = LiveSynth.config.dig("improvise", "start")
    200.times do
      state = DillaImprovisation.walk(moves, state, rng)
      assert moves.key?(state), "#{state} has nowhere to go"
      assert DillaImprovisation::QUALITIES.key?(state.last), "#{state.last} is not a known quality"
    end
  end

  def test_walking_knobs_wander_inside_their_travel
    motion = LiveSynth.config.dig("improvise", "knobs")
    knobs = LiveSynth::Knobs.new(motion, response: {}, rng: Random.new(5))
    values = Array.new(3_000) { |i| knobs.step(0.032, i * 0.032) }
    values.each { |v| assert v.values.all? { |x| x.between?(0.0, 1.0) } }
    assert_operator values.map { |v| v["cutoff"] }.uniq.size, :>, 100, "a walk that does not move is not a knob turning"
  end

  # Asked for, a knob travels to where it was asked over the seconds given.
  def test_a_knob_turn_arrives_over_its_seconds
    knobs = LiveSynth::Knobs.new({}, response: {}, rng: Random.new(1))
    knobs.turn("cutoff", clock: 10.0, seconds: 20.0, by: 0.4)
    assert_in_delta 0.5, knobs.step(0.03, 10.0)["cutoff"], 1e-9
    assert_in_delta 0.7, knobs.step(0.03, 20.0)["cutoff"], 1e-9
    assert_in_delta 0.9, knobs.step(0.03, 40.0)["cutoff"], 1e-9
    assert_raises(ArgumentError) { knobs.turn("volume", clock: 0.0, seconds: 1.0, by: 0.1) }
  end

  # Generic play is the steerable showcase. Explicit improvisation remains
  # the improviser, while named progressions and patches keep their names.
  def test_sentences_become_live_commands
    say = LiveSynth::Say
    ["play", "keep playing", "play something", "play me something with moog patches",
     "play me a chord progression with a few different moog patches",].each do |sentence|
      assert_equal %w[progression moog_improv], say.play_args(sentence), sentence
    end
    assert_equal %w[improvise], say.play_args("improvise")
    assert_equal %w[patch fat_bass], say.play_args("play a moog bass")
    assert_equal %w[progression dilla_love pads=lofi_pad], say.play_args("play a lofi pad morphing through dilla_love")
    assert_equal %w[progression dilla_love family=rhodes], say.play_args("play a rhodes through dilla_love")
    assert_equal %w[improvise], say.play_args("improvise with drums")
    assert_equal %w[improvise family=moog], say.play_args("play it on the minimoog")

    assert_equal %w[progression moog_improv], say.play_args("play music")
    assert_equal 4, LiveSynth.config.dig("progressions", "moog_improv", "master").count { |stage| stage.key?("vcs") }
    assert_equal 3, LiveSynth.config.dig("progressions", "moog_improv", "master").count { |stage| stage.key?("sonitex") }
    assert_equal 1, LiveSynth.config.dig("progressions", "moog_improv", "master").count { |stage| stage.key?("console_stack") }
    assert_equal({ "knob" => "cutoff", "seconds" => 30, "amount" => "+0.35" }, say.knob_command("cutoff", "slowly open the filter"))
    assert_equal "-0.35", say.knob_command("cutoff", "close the filter")["amount"]
    assert_equal({ "toggle" => "drums", "on" => false }, say.steering("drums off"))
    assert_equal({ "lead" => "fm", "preset" => "glass" }, say.steering("fm lead glass"))
  end

  def test_default_improviser_draws_only_source_backed_dilla_or_dangelo_harmony
    keys = LiveSynth.authentic_progression_keys
    refute_empty keys
    assert_includes keys, "dilla_life"
    assert(keys.any? { |key| ARTIST_VERIFIED_PROGRESSIONS.fetch(key.to_sym).fetch(:artist).to_s.include?("D'Angelo") })
    keys.each do |key|
      source = LiveSynth.documented_progression(key)
      assert_operator source.fetch("chords").length, :>=, 2
      assert source.fetch("chords").all? { |symbol| resolve_pad_chord_symbol(symbol) }, key
    end
  end

  def test_reference_improviser_uses_the_registered_dilla_voicing
    score = LiveSynth::Improviser.new(rng: Random.new(7), reference: "dilla_life", pad: "rhodes_tine")
    stage = LiveSynth::Stage.new(rate: RATE, rng: score.rng)
    score.schedule(stage, 0.0)

    expected = resolve_pad_chord_symbol("Bbm9").fetch(:hz).map { |hz| (69 + (12 * Math.log2(hz / 440.0))).round }.uniq
    actual = stage.instance_variable_get(:@voices).first(5).map(&:midi)
    assert_equal expected, actual
  end

  def test_dangelo_showcase_uses_the_richer_reference_and_soft_lead
    source = File.read(dilla("lib/livesets.rb"))
    block = source[source.index('when "dangelo"')...source.index('when "flylo"')]
    assert_includes block, 'reference: "untitled_d_mixolydian_vamp"'
    assert_includes block, '"preset" => "bell"'
    refute_includes block, '"preset" => "metal"'
  end

  def test_bare_dilla_entrypoint_routes_to_showcase
    source = File.read(dilla("dilla.rb"))
    assert_match(/if ARGV\.empty\?.*?live!\(\[["']showcase["']\]\)/m, source)
    assert_match(/LIVE_SYNTH_VERBS = %w\[[^\]]*\bshowcase\b[^\]]*\]\.freeze/, source)
  end

  def test_showcase_covers_the_live_feature_tour
    scenes = LiveSynth::SHOWCASE_SCENES.map(&:first)
    assert_equal %w[dilla_life soulquarians dangelo flylo madlib royksopp moog_dfam memorymoog_organ glass_bell bach], scenes
    source = File.read(dilla("lib/livesets.rb"))
    assert_includes source, 'reference: "dilla_life"'
    assert_includes source, 'reference: "soulquarians_butter"'
    assert_includes source, 'reference: "really_love_bossa_broken"'
    assert_includes source, 'reference: "flylo_camel_documented"'
    assert_includes source, 'reference: "madlib_accordion_loop_documented"'
    assert_includes source, 'Progression.new("royksopp_live"'
    assert_includes source, 'Progression.new("moog_improv"'
    assert_includes source, 'BachMidi::Score.new'
  end

  def test_bare_dilla_entrypoint_routes_to_showcase_before_render_setup
    source = File.read(dilla("dilla.rb"))
    early = source.index("if ARGV.empty?")
    provenance = source.index("DillaProvenance.begin!")
    assert_operator early, :<, provenance, "bare showcase starts before render setup"
    assert_match(/if ARGV\.empty\?.*?live!\(\[["']showcase["']\]\)/m, source)
    assert_match(/if cmd\.nil\?.*?live!\(\[["']showcase["']\]\)/m, source)
    refute_match(/if cmd\.nil\?.*?Bed\.pieces!/m, source)
  end

  def test_play_artist_uses_documented_source_lanes
    table = LiveSynth.config.fetch("play")
    assert_equal "bach_midi", table.fetch("bach")
    assert_equal "reference:dilla_flowers_documented", table.fetch("j_dilla")
    assert_equal "reference:flylo_camel_documented", table.fetch("flying_lotus")
    assert_equal "reference:madlib_accordion_loop_documented", table.fetch("madlib")
    assert_equal "reference:royksopp_what_else_is_there_documented", table.fetch("royksopp")

    source = LiveSynth.documented_progression("dilla_flowers_documented")
    assert_equal %w[Dm9 Am7], source.fetch("chords")
    assert_equal 84, source.fetch("bpm")
  end

  def test_bach_midi_defaults_to_the_fugue_section
    assert_equal "fugue", BachMidi::DEFAULT_SECTION
    assert_equal :fugue, BachMidi::DEFAULT_SECTION.to_sym
  end

  def test_bach_midi_parser_reads_note_events_and_tempo
    Dir.mktmpdir do |dir|
      path = File.join(dir, "bach.mid")
      track = [
        0x00, 0xFF, 0x51, 0x03, 0x07, 0xA1, 0x20,
        0x00, 0x90, 0x3A, 0x5A,
        0x60, 0x80, 0x3A, 0x40,
        0x00, 0xFF, 0x2F, 0x00
      ].pack("C*")
      header = "MThd".b + [6, 1, 1, 96].pack("Nnnn")
      body = "MTrk".b + [track.bytesize].pack("N") + track
      File.binwrite(path, header + body)

      events, length, format = BachMidi.parse(path)
      assert_equal 1, events.length
      note = events.first
      assert_equal 58, note.fetch(:pitch)
      assert_in_delta 0.0, note.fetch(:at), 0.0001
      assert_in_delta 0.5, note.fetch(:held), 0.0001
      assert_in_delta 0.5, length, 0.0001
      assert_equal 1, format
    end
  end

  def test_bach_score_schedules_notes_with_a_rolling_lookahead
    events = [
      { at: 0.0, held: 0.2, pitch: 50, gain: 0.3 },
      { at: 0.9, held: 0.2, pitch: 57, gain: 0.3 },
      { at: 2.0, held: 0.2, pitch: 62, gain: 0.3 },
    ]
    score = BachMidi::Score.new(events:, length: 2.2, rng: Random.new(1), patch: "memorymoog_organ")
    stage = LiveSynth::Stage.new(rate: RATE, rng: score.rng)

    score.schedule(stage, 0.0)
    assert_equal 2, stage.instance_variable_get(:@voices).length
    refute score.finished?(0.0)

    score.schedule(stage, 1.1)
    assert_equal 3, stage.instance_variable_get(:@voices).length
    refute score.finished?(2.0)

    assert score.finished?(2.2)
  end

  def test_documented_artist_lane_uses_the_good_improviser_renderer
    score = LiveSynth::Improviser.new(
      rng: Random.new(9),
      reference: "dilla_flowers_documented",
      pad: "rhodes_tine"
    )
    samples = with_live_dir { perform(score, seconds: 3.0) }
    assert_operator samples.size, :>=, 3 * RATE * 2
    assert_operator samples.map(&:abs).max, :>, 1_000
  end

  def test_steering_with_nothing_playing_says_so
    with_live_dir do
      assert_equal "nothing is playing", LiveSynth::Say.call("slowly open the filter")
      assert_equal "nothing is playing", LiveSynth::Say.call("stop")
    end
  end

  # The main sound plays as frozen: a knob asked of it is refused in words,
  # and stop still ends it.
  def test_the_frozen_default_cannot_be_steered_and_still_stops
    with_live_dir do |dir|
      player = Process.spawn(RbConfig.ruby, "-e", "sleep 30", pgroup: true)
      File.write(File.join(dir, "player.json"),
                 JSON.generate("pid" => player, "what" => "the standard default (liveset)", "steerable" => false))
      assert_match(/plays as frozen/, LiveSynth::Say.call("slowly open the filter"))
      assert_match(/stopped the standard default/, LiveSynth::Say.call("stop"))
      Process.wait(player)
    end
  end

  # The frozen set and the Röyksopp set play from inside the engine now:
  # `live standard` is what `live default` re-execs into, `live royksopp` is
  # the pads that were the default before it.
  def test_standard_and_royksopp_verbs_dispatch_to_their_players
    with_live_dir do
      standard_ran = royksopp_ran = false
      LivesetStandard.stub(:run, -> { standard_ran = true }) do
        RoyksoppLive.stub(:call, -> { royksopp_ran = true }) do
          LiveSynth.main(["standard"])
          LiveSynth.main(["royksopp"])
        end
      end
      assert standard_ran, "live standard runs the folded liveset"
      assert royksopp_ran, "live royksopp runs the folded Röyksopp player"
    end
  end

  # `live take <name>` plays a frozen take out of the engine's TOC.
  def test_the_take_verb_plays_the_named_take
    with_live_dir do
      played = nil
      DillaTakes.stub(:play, ->(name) { played = name }) do
        LiveSynth.main(["take", "loved_moog_loop"])
      end
      assert_equal "loved_moog_loop", played
    end
  end

  # MASTER's main sound is the frozen liveset the operator last made the
  # default, and every take before it: all frozen inside the engine, as they
  # were heard. A pin is sha256[0, 12] of the take's unwrapped script --
  # path-independent, so the fold's renames live outside it.
  FROZEN = {
    "liveset_161326bb356a" => "56faac0fcfaa",
    "liveset_4abbb73e" => "a17c1cf6afb2",
    "liveset_5613fe64b642" => "5094f13aa2ea",
    "liveset_5aa16356c296" => "ae88a4ff0963",
    "liveset_68eccd04098e" => "37c30667fd55",
    "liveset_7b5069a1bf3b" => "330916114a3b",
    "liveset_864969335d0f" => "853306a49dbd",
    "liveset_db4ddf1a" => "eeea14de09e2",
    "loved_moog_loop" => "2a9a6d210594",
    "moog_dfam_loop" => "a84cc8cc7169",
  }.freeze

  def dilla(path) = File.join(__dir__, "..", "dilla", path)

  # The unwrapped script a frozen take's module holds: the module scaffolding
  # comes off, `def self.run` unfolds to the body the take ran, and the
  # run def's argv returns to the ARGV the original file read.
  def take_script(stem)
    name = stem.split("_").map(&:capitalize).join
    src = File.read(dilla("dilla.rb"))
    from = src.index("\n  module #{name}\n") or abort "no module #{name}"
    region = src[(from + 1)..].lines
    to = region.index("  end\n") or abort "no end for #{name}"
    body = region[0..to].map { |line| line.sub(/\A  /, "") }[1..-2]
    body.shift if body.first.start_with?("# takes/") # the provenance line
    body.shift if body.first == "\n"
    idx = body.index { |line| line.start_with?("  def self.run(") } or abort "no run def for #{name}"
    last_end = body.rindex { |line| line == "  end\n" } or abort "no run end for #{name}"
    (body[0...idx] + body[(idx + 1)...last_end]).map do |line|
      line = line.sub(/^(\s*)def self\./) { "#{Regexp.last_match(1)}def " }
      line.gsub(/\bargv\b/, "ARGV")
    end.join
  end

  def test_the_frozen_takes_are_as_frozen
    FROZEN.each { |stem, sha| assert_equal sha, Digest::SHA256.hexdigest(take_script(stem))[0, 12], stem }
  end

  # The numbers the operator froze, read off the file, so a change to any of
  # them is a change somebody has to make here too, on purpose. The set plays
  # from inside the engine now, indented under its module, so the anchors allow
  # the two leading spaces.
  def test_the_main_sound_keeps_its_numbers
    src = File.read(dilla("dilla.rb")).partition("module LivesetStandard").last
    src = src.partition("\nend\n").first
    pins = {
      /^\s*RATE = 32_000$/ => "32 kHz", /^\s*BLOCK = 1_024$/ => "1024-frame blocks", /^\s*BPM = 118$/ => "118 BPM",
      %r{^\s*BAR = 8 \* 60\.0 / BPM$} => "two bars to a chord", %r{^\s*DFAM_STEP = BAR / 32} => "the DFAM in sixteenths",
      /^\s*DFAM_LEVEL = 0\.16$/ => "the DFAM at 0.16", /^\s*KICKS_ON = false$/ => "the kicks off", /^\s*CUTS_ON = false$/ => "the crossfader off",
      /^\s*LEADS_ON = true$/ => "the leads on", /step \* 0\.7, 0\.08, bass: :arp/ => "the arp at 0.08",
      /^\s*MORPH_CHORDS = 4$/ => "a new pad every four chords", /^\s*LEAD_GLIDE_S = 6\.0$/ => "a lead glide every six seconds",
      /^\s*BREATH_DEPTH = 0\.3$/ => "the chords breathing 30%", /aexciter=amount=1\.2:drive=5:freq=3500:ceil=16000/ => "the air",
      /def vcs\(depth:, smear:, db: 0\.0\)/ => "level-neutral VCS",
      /opus3_strings:/ => "the Opus strings", /matriarch_stabs:/ => "the Matriarch stabs", /memorymoog_organ:/ => "the Memorymoog organ",
      /grandmother_sweep:/ => "the Grandmother sweep", /vox_humana:/ => "the vox humana",
    }
    pins.each { |pattern, what| assert_match pattern, src, what }
  end

  # A take, seeded and captured before its ffmpeg console, against the
  # engine's progression of the same name: equal sample for sample. The take
  # runs from the module now folded into dilla.rb -- the script its TOC entry
  # unwraps to. Kernels the take shares with its old file are seeded alike:
  # the per-stream rewrites are anchored to whole lines, because the module
  # sections carry knob_rng and dfam_rng relatives a bare substring would hit.
  def reference_samples(take, seconds, seed)
    src = "$LOAD_PATH.unshift #{File.expand_path(dilla("lib")).inspect}\nrequire \"sound\"\n\nsrand(#{seed})\n\n#{take_script(take)}"
    src = src.gsub(/^( *)dfam_rng = Random\.new$/) { "#{Regexp.last_match(1)}dfam_rng = Random.new(#{seed})" }
             .gsub(/^( *)rng = Random\.new$/) { "#{Regexp.last_match(1)}rng = Random.new(#{seed})" }
             .gsub(/^( *)knob_rng = Random\.new$/) { "#{Regexp.last_match(1)}knob_rng = Random.new(#{seed} ^ 0x0dd)" }
    src = src.sub(/^( *)dfam_rng = Random\.new\(#{seed}\)$/, "\\0\nDFAM_NOISE = Random.new(#{seed} ^ 0xdfa)")
             .sub("(0.18 * (rand * 2.0 - 1.0))", "(0.18 * (DFAM_NOISE.rand * 2.0 - 1.0))")
    src = src.sub(/^\s*log = File\.open\(.*$/, "log = File.open(File::NULL, \"w\")")
    Dir.mktmpdir do |dir|
      raw = File.join(dir, "take.raw")
      src = src.sub(/^\s*sox = IO\.popen\(.*$/, "sox = File.open(#{raw.inspect}, \"wb\")")
      src = src.sub(/^\s*frames = .*$/) { |line| "#{line}\nframes = [frames, (#{seconds} * RATE).to_i].min" }
      File.write(File.join(dir, "take.rb"), src)
      assert system(RbConfig.ruby, "--yjit", File.join(dir, "take.rb"), err: File::NULL), "#{take} ran"
      File.binread(raw).unpack("s<*")
    end
  end

  def engine_samples(progression, seconds, seed)
    with_live_dir { perform(LiveSynth::Progression.new(progression, rng: Random.new(seed), loops: 0), seconds:) }
  end

  # Sixty-four blocks each, about two seconds: long enough for every layer
  # the take has to have sounded, short enough for the suite. Minutes of each
  # were compared the same way when the engine was written. Whole blocks,
  # because a take cut mid-block sequences its DFAM against the short block.
  WINDOW = 64 * 1024 / 32_000.0

  def assert_plays_the_take(take, progression)
    take_samples = reference_samples(take, WINDOW, 5)
    ours = engine_samples(progression, WINDOW, 5)
    assert_operator take_samples.size, :>, 0
    assert_equal take_samples, ours.first(take_samples.size), "#{progression} is #{take}"
  end

  def test_soul_jazz_six_is_the_loved_loop = assert_plays_the_take("loved_moog_loop", "soul_jazz_six")

  def test_moog_dfam_is_the_dfam_loop = assert_plays_the_take("moog_dfam_loop", "moog_dfam")

  def test_moog_improv_is_the_standard_before_liveset = assert_plays_the_take("liveset_db4ddf1a", "moog_improv")

  # Seeded on pitch and start, the written progression is the same take
  # twice, and it is sound, not silence or a fault.
  def test_the_approved_progression_is_repeatable
    first = with_live_dir { perform(LiveSynth::Progression.new("soul_jazz_six", rng: Random.new(1), loops: 1), seconds: 3.0) }
    again = with_live_dir { perform(LiveSynth::Progression.new("soul_jazz_six", rng: Random.new(2), loops: 1), seconds: 3.0) }
    assert_equal first, again
    assert_operator first.map(&:abs).max, :>, 1_000
    assert_operator first.map(&:abs).max, :<=, LiveSynth.stream["master_scale"]
  end

  def test_improvising_on_moog_patches_sounds
    samples = with_live_dir { perform(LiveSynth::Improviser.new(rng: Random.new(9), family: "moog"), seconds: 3.0) }
    assert_operator samples.size, :>=, 3 * RATE * 2
    assert_operator samples.map(&:abs).max, :>, 1_000
  end

  # A legato Model D line is one voice gliding, not a voice per note.
  def test_a_legato_patch_plays_its_phrase_as_one_voice
    with_live_dir do
      demo = LiveSynth::Demo.new("lucky_man", rng: Random.new(4))
      stage = LiveSynth::Stage.new(rate: RATE, rng: demo.rng)
      demo.schedule(stage, 0.0)
      assert_equal 1, stage.instance_variable_get(:@voices).size
    end
  end
end
