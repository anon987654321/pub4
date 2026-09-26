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

  # Nothing named is the main sound, and so are the moog patches it is made
  # of; a named progression, patch, family or part asks for that instead.
  def test_sentences_become_live_commands
    say = LiveSynth::Say
    ["play", "improvise", "keep playing", "play something", "play me something with moog patches",
     "play me a chord progression with a few different moog patches",].each do |sentence|
      assert_equal %w[default], say.play_args(sentence), sentence
    end
    assert_equal %w[patch fat_bass], say.play_args("play a moog bass")
    assert_equal %w[progression dilla_love pads=lofi_pad], say.play_args("play a lofi pad morphing through dilla_love")
    assert_equal %w[progression dilla_love family=rhodes], say.play_args("play a rhodes through dilla_love")
    assert_equal %w[improvise], say.play_args("improvise with drums")
    assert_equal %w[improvise family=moog], say.play_args("play it on the minimoog")
    assert_equal({ "knob" => "cutoff", "seconds" => 30, "amount" => "+0.35" }, say.knob_command("cutoff", "slowly open the filter"))
    assert_equal "-0.35", say.knob_command("cutoff", "close the filter")["amount"]
    assert_equal({ "toggle" => "drums", "on" => false }, say.steering("drums off"))
    assert_equal({ "lead" => "fm", "preset" => "glass" }, say.steering("fm lead glass"))
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
                 JSON.generate("pid" => player, "what" => "the standard default (liveset.rb)", "steerable" => false))
      assert_match(/plays as frozen/, LiveSynth::Say.call("slowly open the filter"))
      assert_match(/stopped the standard default/, LiveSynth::Say.call("stop"))
      Process.wait(player)
    end
  end

  # MASTER's main sound is MASTER/tools/dilla/liveset.rb as the operator last made it
  # the default, and every take before it is kept as it was heard.
  FROZEN = {
    "liveset.rb" => "23c0aa7e298f",
    "takes/liveset_161326bb356a.rb" => "683a88ef3edc",
    "takes/liveset_4abbb73e.rb" => "6b4d7f5cba19",
    "takes/liveset_5613fe64b642.rb" => "9499edf5943c",
    "takes/liveset_5aa16356c296.rb" => "13eb699bf265",
    "takes/liveset_68eccd04098e.rb" => "fe8e97125f8e",
    "takes/liveset_7b5069a1bf3b.rb" => "b61cf8202ffe",
    "takes/liveset_864969335d0f.rb" => "e616cc3bdd53",
    "takes/liveset_db4ddf1a.rb" => "eefa23e337dd",
    "takes/loved_moog_loop.rb" => "08c384cd563a",
    "takes/moog_dfam_loop.rb" => "542c589044c4",
  }.freeze

  def dilla(path) = File.join(__dir__, "..", "dilla", path)

  def test_the_frozen_files_are_as_frozen
    FROZEN.each { |path, sha| assert_equal sha, Digest::SHA256.file(dilla(path)).hexdigest[0, 12], path }
  end

  # The numbers the operator froze, read off the file, so a change to any of
  # them is a change somebody has to make here too, on purpose.
  def test_the_main_sound_keeps_its_numbers
    src = File.read(dilla("liveset.rb"))
    pins = {
      /^RATE = 32_000$/ => "32 kHz", /^BLOCK = 1_024$/ => "1024-frame blocks", /^BPM = 118$/ => "118 BPM",
      %r{^BAR = 8 \* 60\.0 / BPM$} => "two bars to a chord", %r{^DFAM_STEP = BAR / 32} => "the DFAM in sixteenths",
      /^DFAM_LEVEL = 0\.16$/ => "the DFAM at 0.16", /^KICKS_ON = false$/ => "the kicks off", /^CUTS_ON = false$/ => "the crossfader off",
      /^LEADS_ON = true$/ => "the leads on", /step \* 0\.7, 0\.08, bass: :arp/ => "the arp at 0.08",
      /^MORPH_CHORDS = 4$/ => "a new pad every four chords", /^LEAD_GLIDE_S = 6\.0$/ => "a lead glide every six seconds",
      /^BREATH_DEPTH = 0\.3$/ => "the chords breathing 30%", /aexciter=amount=1\.2:drive=5:freq=3500:ceil=16000/ => "the air",
      /def vcs\(depth:, smear:, db: 0\.0\)/ => "level-neutral VCS",
      /opus3_strings:/ => "the Opus strings", /matriarch_stabs:/ => "the Matriarch stabs", /memorymoog_organ:/ => "the Memorymoog organ",
      /grandmother_sweep:/ => "the Grandmother sweep", /vox_humana:/ => "the vox humana",
    }
    pins.each { |pattern, what| assert_match pattern, src, what }
  end

  # A take, seeded and captured before its ffmpeg console, against the
  # engine's progression of the same name: equal sample for sample.
  def reference_samples(take, seconds, seed)
    src = File.read(dilla("takes/#{take}"))
    lib = File.expand_path(dilla("lib"))
    # Whatever load path the take carries, it runs from a scratch copy, so its
    # own relative path would point nowhere: the engine library stands in.
    src = src.sub(/^\$LOAD_PATH\.unshift .*$/) { "$LOAD_PATH.unshift #{lib.inspect}" }
    src = src.sub("dfam_rng = Random.new\n", "dfam_rng = Random.new(#{seed})\nDFAM_NOISE = Random.new(#{seed} ^ 0xdfa)\n")
    src = src.sub("rng = Random.new\n", "rng = Random.new(#{seed})\n").sub("(0.18 * (rand * 2.0 - 1.0))", "(0.18 * (DFAM_NOISE.rand * 2.0 - 1.0))")
    src = src.sub(/^LOG = .*$/, "LOG = File.open(File::NULL, \"w\")")
    Dir.mktmpdir do |dir|
      raw = File.join(dir, "take.raw")
      src = src.sub(/^sox = IO\.popen\(.*$/, "sox = File.open(#{raw.inspect}, \"wb\")")
      src = src.sub(/^frames = .*$/) { |line| "#{line}\nframes = [frames, (#{seconds} * RATE).to_i].min" }
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

  def test_soul_jazz_six_is_the_loved_loop = assert_plays_the_take("loved_moog_loop.rb", "soul_jazz_six")

  def test_moog_dfam_is_the_dfam_loop = assert_plays_the_take("moog_dfam_loop.rb", "moog_dfam")

  def test_moog_improv_is_the_standard_before_liveset = assert_plays_the_take("liveset_db4ddf1a.rb", "moog_improv")

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
