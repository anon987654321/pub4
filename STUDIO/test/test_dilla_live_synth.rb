# frozen_string_literal: true

require_relative "dilla_helper"
require_relative "../dilla/lib/livesets"
require "stringio"

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

  def test_sentences_become_live_commands
    say = LiveSynth::Say
    assert_equal %w[patch fat_bass], say.play_args("play a moog bass")
    assert_equal %w[progression dilla_love pads=lofi_pad], say.play_args("play a lofi pad morphing through dilla_love")
    assert_equal %w[improvise family=moog], say.play_args("play me something with moog patches")
    assert_equal %w[progression soul_jazz_six family=moog],
                 say.play_args("play me a chord progression with a few different moog patches")
    assert_equal %w[progression dilla_love family=rhodes], say.play_args("play a rhodes through dilla_love")
    assert_equal({ "knob" => "cutoff", "seconds" => 30, "amount" => "+0.35" }, say.knob_command("cutoff", "slowly open the filter"))
    assert_equal "-0.35", say.knob_command("cutoff", "close the filter")["amount"]
  end

  def test_steering_with_nothing_playing_says_so
    with_live_dir do
      assert_equal "nothing is playing", LiveSynth::Say.call("slowly open the filter")
      assert_equal "nothing is playing", LiveSynth::Say.call("stop")
    end
  end

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
