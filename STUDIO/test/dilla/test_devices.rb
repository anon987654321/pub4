# frozen_string_literal: true

require_relative "helper"

# The devices, and the two properties that decide whether they are real.
#
# Not "does it produce output" -- everything produces output. These pin the
# things that would break silently: that a modulation route reaches a parameter
# ffmpeg will actually accept at runtime, that a macro cannot name a knob nothing
# reads, and that a device which claims to rearrange notes does not invent or
# lose any.
class TestDevices < Minitest::Test
  # ------------------------------------------------------------- modulation

  # The failure this catches is the one that cost the first measurement: a
  # command sent to a filter that does not accept it is ACCEPTED by ffmpeg and
  # does nothing, so the modulation measures as a flat line and reports success.
  def test_a_route_to_a_non_runtime_parameter_is_refused
    matrix = DillaModulation::Matrix.new
    matrix.lfo(:l, rate_hz: 1.0)

    error = assert_raises(ArgumentError) do
      # aphaser has no T-flagged options at all in ffmpeg 8.1.1.
      matrix.route(:l, instance: "x", filter: "aphaser", param: "speed")
    end
    assert_match(/not runtime-settable|has no parameter/, error.message)
  end

  def test_a_route_to_a_runtime_parameter_is_allowed
    matrix = DillaModulation::Matrix.new
    matrix.lfo(:l, rate_hz: 1.0)
    matrix.route(:l, instance: "warp", filter: "lowpass", param: "frequency", base: 900.0)

    assert_equal 1, matrix.routes.length
  end

  # asendcmd's target is the INSTANCE name. Targeting the bare id sends the
  # command nowhere, reports nothing, and measures dead flat -- which is exactly
  # what happened the first time this was built.
  def test_commands_name_the_filter_instance_not_the_bare_id
    matrix = DillaModulation::Matrix.new
    matrix.lfo(:l, rate_hz: 2.0)
    matrix.route(:l, instance: "warp", filter: "lowpass", param: "frequency",
                     base: 900.0, min: 200.0, max: 8000.0)
    line = matrix.command_lines(duration: 0.5).first

    assert_includes line, "lowpass@warp frequency"
    refute_match(/\[enter\] warp /, line)
  end

  # Every value has to land inside the parameter's declared range, at every
  # point of every shape, or ffmpeg clamps it silently and the modulation has a
  # flat spot nobody can see in the source.
  def test_no_emitted_value_leaves_the_declared_range
    matrix = DillaModulation::Matrix.new
    matrix.lfo(:l, rate_hz: 4.0, family: :straight, morph: 0.0) # square: the extremes
    matrix.route(:l, instance: "warp", filter: "lowpass", param: "frequency",
                     base: 900.0, depth: 1.0, min: 200.0, max: 8000.0, scale: :log)
    values = matrix.command_lines(duration: 2.0).map { |l| l.split.last.chomp(";").to_f }

    refute_empty values
    assert_operator values.min, :>=, 200.0
    assert_operator values.max, :<=, 8000.0
  end

  # The stepped family exists because neither other family can hold still. Every
  # shape in it has to stay in range like any other, or a route clamps into a
  # flat top nobody chose.
  def test_stepped_shapes_stay_in_range_and_hold_their_value
    DillaModulation::STEPPED.each do |shape|
      (0..64).each do |p|
        v = DillaModulation.send(shape, p / 64.0)

        assert_operator v, :>=, -1.0001, "#{shape} at #{p / 64.0}"
        assert_operator v, :<=, 1.0001, "#{shape} at #{p / 64.0}"
      end
    end
  end

  # Sample-and-hold read three times for one phase must give one answer. A
  # stateful generator would give each route a different number, which would make
  # one source behave as several and is the bug that is hardest to see.
  def test_sample_and_hold_is_stable_for_a_given_phase
    assert_equal 1, 5.times.map { DillaModulation.sample_hold(0.42) }.uniq.length
    refute_equal DillaModulation.sample_hold(0.42), DillaModulation.sample_hold(0.92)
  end

  # It has to actually hold -- a value that changed every sample would be noise
  # wearing the name of a sequencer.
  def test_sample_and_hold_holds
    inside_one_step = (0...6).map { |i| DillaModulation.sample_hold(0.01 + (i * 0.005)) }

    assert_equal 1, inside_one_step.uniq.length
  end

  # A fan-out is one source reaching several parameters, each with its own depth.
  # Equal depths everywhere would be one modulation applied N times.
  def test_a_fan_reaches_every_destination_with_its_own_depth
    matrix = DillaModulation::Matrix.new
    matrix.lfo(:one, rate_hz: 0.5)
    matrix.fan(:one, [
                 { instance: "a", filter: "lowpass", param: "frequency", base: 900.0, depth: 1.0 },
                 { instance: "b", filter: "equalizer", param: "gain", base: 0.0, depth: 0.4 },
               ])

    assert_equal 2, matrix.routes.length
    assert_equal [1.0, 0.4], matrix.routes.map(&:depth)
    assert_equal 1, matrix.routes.map { |r| r.source.id }.uniq.length
  end

  # The follower normalises against a STATED window, so the same beat drives a
  # route the same way regardless of how loud the file was mastered.
  def test_the_envelope_follower_is_normalised_to_its_window
    points = [[0.0, -60.0], [1.0, -30.0], [2.0, 0.0]]
    # Reproduce the mapping the follower applies, and check both ends land.
    mapped = points.map do |t, level|
      [t, (((level.clamp(-50.0, -8.0) + 50.0) / 42.0) * 2.0) - 1.0]
    end

    assert_in_delta(-1.0, mapped[0][1], 1e-9, "below the floor pins to -1")
    assert_in_delta 1.0, mapped[2][1], 1e-9, "above the ceiling pins to +1"
    assert_operator mapped[1][1], :>, -1.0
    assert_operator mapped[1][1], :<, 1.0
  end

  # A rate in bars and beats. Every modulation this engine wants is musical, and
  # a rate in hertz drifts against everything else the moment the tempo moves.
  def test_sync_rates_resolve_to_the_right_period
    bpm = 88.0
    beat = 60.0 / bpm
    bar = beat * 4
    {
      "1/4" => beat, "1/8" => beat / 2, "1/16" => beat / 4,
      "1/1" => bar, "1bar" => bar, "4bar" => bar * 4, "2b" => bar * 2,
    }.each do |spec, seconds|
      assert_in_delta seconds, 1.0 / DillaModulation.sync_hz(spec, bpm), 1e-9, spec
    end
  end

  # T shortens a value to two thirds so the RATE rises by half; a dot lengthens
  # it by half so the rate falls to two thirds. Getting those the wrong way round
  # is the classic error and would be inaudible as a bug and obvious as a feel.
  def test_triplets_are_faster_and_dots_are_slower
    plain = DillaModulation.sync_hz("1/8", 88.0)

    assert_in_delta plain * 1.5, DillaModulation.sync_hz("1/8T", 88.0), 1e-9
    assert_in_delta plain * (2.0 / 3.0), DillaModulation.sync_hz("1/8.", 88.0), 1e-9
  end

  def test_a_number_is_still_hertz_and_garbage_is_refused
    assert_in_delta 0.25, DillaModulation.sync_hz(0.25, 88.0), 1e-9
    assert_in_delta 0.25, DillaModulation.sync_hz("0.25", 88.0), 1e-9
    assert_raises(ArgumentError) { DillaModulation.sync_hz("nonsense", 88.0) }
  end

  # The point of syncing: the same division is a different number of hertz at a
  # different tempo, and tracks a rotation whose BPM changes per slot.
  def test_a_synced_rate_follows_the_tempo
    slow = DillaModulation.sync_hz("1/4", 80.0)
    fast = DillaModulation.sync_hz("1/4", 160.0)

    assert_in_delta slow * 2, fast, 1e-9
  end

  # A shape that leaves -1..1 would push every route past its range and be
  # clamped into a flat top, which is a shape nobody chose.
  def test_every_lfo_shape_stays_within_minus_one_and_one
    DillaModulation::FAMILIES.each do |family, shapes|
      (0..20).each do |m|
        (0..64).each do |p|
          v = DillaModulation.morphed(family, m / 20.0, p / 64.0)

          assert_operator v, :>=, -1.0001, "#{family} morph #{m / 20.0} phase #{p / 64.0} (#{shapes})"
          assert_operator v, :<=, 1.0001, "#{family} morph #{m / 20.0} phase #{p / 64.0}"
        end
      end
    end
  end

  # A morph of 0 has to BE the first shape and 1 the last, or the crossfade is
  # off by a segment and no position gives you the shape you asked for.
  def test_morph_endpoints_are_the_named_shapes
    assert_in_delta DillaModulation.square(0.25),
                    DillaModulation.morphed(:straight, 0.0, 0.25), 1e-9
    assert_in_delta DillaModulation.ramp(0.25),
                    DillaModulation.morphed(:straight, 1.0, 0.25), 1e-9
    assert_in_delta DillaModulation.sine(0.25),
                    DillaModulation.morphed(:curved, 1.0 / 3.0, 0.25), 1e-9
  end

  # modulate keeps the operator's number as the centre; remote replaces it.
  # Collapsing the two is what makes a modulated parameter untunable.
  def test_modulate_centres_on_base_and_remote_ignores_it
    matrix = DillaModulation::Matrix.new
    matrix.lfo(:l, rate_hz: 1.0, family: :curved, morph: 1.0 / 3.0) # sine
    matrix.route(:l, instance: "a", filter: "equalizer", param: "gain",
                     base: 3.0, depth: 0.5, mode: :modulate, min: -12.0, max: 12.0)
    matrix.route(:l, instance: "b", filter: "equalizer", param: "gain",
                     base: 3.0, depth: 0.5, mode: :remote, min: -12.0, max: 12.0)
    modulated, remote = matrix.routes

    # sine at phase 0 is 0, so a modulate route sits exactly on its base.
    assert_in_delta 3.0, modulated.value_at(0.0), 1e-6
    # ...and a remote route sits at the middle of its range regardless of base.
    assert_in_delta 0.0, remote.value_at(0.0), 1e-6
  end

  # ------------------------------------------------------------------ hocket

  def test_hocket_loses_no_notes_and_invents_none
    events = (0...48).map { |i| [i * 0.25, 0.7, { hz: [220.0 + i] }, 0.2] }
    MidiDevices::Hocket::MODES.each do |mode|
      split = MidiDevices::Hocket.split(events, voices: 4, mode:, hold: 2)

      assert_equal events.length, split.sum(&:length), "#{mode} changed the note count"
      assert_equal events.map { |e| e[2][:hz] }.sort,
                   split.flatten(1).map { |e| e[2][:hz] }.sort, "#{mode} altered a pitch"
    end
  end

  # Every voice has to get something, or the "ensemble" is one player and three
  # silent patches -- which renders fine and sounds like nothing happened.
  def test_every_voice_receives_notes
    events = (0...64).map { |i| [i * 0.25, 0.7, { hz: [220.0] }, 0.2] }
    MidiDevices::Hocket::MODES.each do |mode|
      split = MidiDevices::Hocket.split(events, voices: 4, mode:)

      assert(split.all? { |v| v.length.positive? }, "#{mode} left a voice empty")
    end
  end

  # The pendulum turns at the ends. If it repeated the end voice instead, that
  # voice would get twice the notes and the travel would stop reading as travel.
  def test_pendulum_visits_the_ends_half_as_often
    events = (0...80).map { |i| [i * 0.25, 0.7, { hz: [220.0] }, 0.2] }
    counts = MidiDevices::Hocket.split(events, voices: 4, mode: :pendulum).map(&:length)

    assert_operator counts.first, :<, counts[1], "the first voice should be the rarest"
    assert_operator counts.last, :<, counts[2], "the last voice should be the rarest"
  end

  # ---------------------------------------------------------------- midi bag

  def test_the_bag_takes_time_from_one_source_and_pitch_from_the_other
    pitches = (0...4).map { |i| [i * 9.9, 0.9, { hz: [220.0 * (i + 1)] }, 5.0] }
    timing  = (0...16).map { |i| [i * 0.25, 0.4, { hz: [999.0] }, 0.1] }
    out = MidiDevices::Bag.apply(pitches:, timing:, order: :cycle)

    assert_equal timing.map(&:first), out.map(&:first), "times must come from the timing source"
    assert_equal timing.map(&:last), out.map(&:last), "sustains must come from the timing source"
    assert_empty(out.map { |e| e[2][:hz] }.flatten - pitches.flat_map { |e| e[2][:hz] },
                 "every pitch must come from the bag")
    refute_includes out.flat_map { |e| e[2][:hz] }, 999.0, "the timing source's own pitch must not survive"
  end

  def test_rests_remove_notes_rather_than_silencing_them
    pitches = [[0.0, 0.9, { hz: [220.0] }, 1.0]]
    timing  = (0...200).map { |i| [i * 0.1, 0.5, { hz: [1.0] }, 0.05] }
    out = MidiDevices::Bag.apply(pitches:, timing:, rests: 0.5, seed: 11)

    assert_operator out.length, :<, timing.length
    assert_operator out.length, :>, 0
    refute(out.any? { |e| e[1].to_f.zero? }, "a rest is a missing note, not a note at zero velocity")
  end

  # Fitting to the chord must move pitch CLASS and keep register. Collapsing a
  # two-octave phrase into the chord's own octave is the failure mode.
  def test_chord_fitting_keeps_the_register
    low  = { hz: [110.0] }
    high = { hz: [1760.0] }
    target = { hz: [261.63, 329.63, 392.0] } # C major
    [low, high].each do |chord|
      fitted = MidiDevices::Bag.fit_to_chord(chord, target)
      octaves = Math.log2(fitted[:hz].first / chord[:hz].first).abs

      assert_operator octaves, :<, 0.5, "fitting moved #{chord[:hz]} by #{octaves.round(2)} octaves"
    end
  end

  # ------------------------------------------------------------ copy machine

  def test_the_first_copy_is_the_sound_itself
    plan = CopyMachine.plan(copies: 8, family: :spray)
    anchor = plan.first

    assert_equal 1.0, anchor.ratio
    refute anchor.reverse
    assert_equal 0.0, anchor.pan
    assert_equal 0, anchor.delay_ms
  end

  def test_every_copy_stays_inside_the_playable_ratio_range
    CopyMachine::RATIOS.each_key do |family|
      CopyMachine.plan(copies: 16, family:).each do |copy|
        assert_operator copy.ratio, :>=, CopyMachine::MIN_RATIO, "#{family} copy #{copy.index}"
        assert_operator copy.ratio, :<=, CopyMachine::MAX_RATIO, "#{family} copy #{copy.index}"
      end
    end
  end

  # amix's own default rescales by input count. Without normalize=0 an
  # eight-copy cloud would arrive a third of the level of a two-copy one, which
  # reads as "more copies did nothing".
  def test_the_graph_disables_amix_normalisation
    graph = CopyMachine.filter_complex(CopyMachine.plan(copies: 4), input: "0:a")

    assert_includes graph, "normalize=0"
    assert_includes graph, "asplit=4"
  end

  # -------------------------------------------------------------- macros

  # The defect this exists to prevent, stated as a test: `dilla taste` names
  # MASTER_TARGET_LUFS, MASTER_TARGET_LRA and SAMPLE_LOOP_LP as the knobs that
  # move its dimensions, and the engine reads none of the three.
  def test_no_macro_names_a_knob_the_engine_never_reads
    assert DillaMacros.verify!
  end

  # The same guard, for the other place that hands the operator a knob name.
  #
  # `dilla taste` ends every finding with the control that moves that dimension,
  # and two of them named knobs the engine reads nowhere -- MASTER_TARGET_LRA and
  # MASTER_TARGET_LUFS -- on the two dimensions an operator is most likely to act
  # on. The advice ran, read as authoritative, and pointed at nothing.
  #
  # Uppercase tokens only: the field is prose with knob names in it ("GHOST_TIER,
  # DRUM_CHOPS, the drum feel"), so the prose is skipped and the names are not.
  def test_taste_never_names_a_knob_the_engine_never_reads
    missing = DillaTaste::DIMENSIONS.flat_map do |dimension, spec|
      spec[:knob].to_s.scan(/\b[A-Z][A-Z0-9_]{3,}\b/).reject { |n| DillaKnobs[n] }
                 .map { |n| "#{dimension} -> #{n}" }
    end

    assert_empty missing,
                 "taste names a knob nothing reads; the advice will be followed and do nothing"
  end

  def test_a_macro_sweeps_between_its_own_ends
    DillaMacros::MACROS.each do |name, targets|
      low = DillaMacros.resolve(name, 0.0)
      high = DillaMacros.resolve(name, 1.0)
      targets.each do |t|
        assert_in_delta t.floor, low[t.knob].to_f, 0.51, "#{name}/#{t.knob} at 0"
        assert_in_delta t.ceiling, high[t.knob].to_f, 0.51, "#{name}/#{t.knob} at 1"
      end
    end
  end

  # A macro must not be able to set a knob outside the clamp the engine declares
  # for it, or the macro is asking for a value the engine will quietly refuse.
  def test_macro_ranges_sit_inside_the_knobs_own_clamps
    DillaMacros::MACROS.each do |name, targets|
      targets.each do |t|
        range = DillaKnobs[t.knob]&.range or next

        assert_operator t.floor, :>=, range.first, "#{name}/#{t.knob} floor is below the knob's clamp"
        assert_operator t.ceiling, :<=, range.last, "#{name}/#{t.knob} ceiling is above the knob's clamp"
      end
    end
  end

  # P_4L's variation: the spread has to stay centred on what was asked for, or
  # the variation knob is a second and secret macro knob.
  def test_variation_spreads_without_moving_the_centre
    values = DillaMacros.spread(0.5, amount: 0.4, count: 8, seed: 7)

    assert_in_delta 0.5, values.sum / values.length, 0.02
    assert_operator values.uniq.length, :>, 1
    assert(values.all? { |v| v.between?(0.0, 1.0) })
  end

  # apply! must not overwrite what the operator set by hand -- the macro is the
  # coarse control and an explicit export is the fine one.
  def test_apply_keeps_a_hand_set_knob
    previous = ENV.fetch("KICK_GAIN", nil)
    ENV["KICK_GAIN"] = "0.99"
    result = DillaMacros.apply!({ weight: 0.2 })

    assert_equal "0.99", ENV["KICK_GAIN"]
    assert(result[:skipped].any? { |s| s.start_with?("KICK_GAIN") })
  ensure
    previous.nil? ? ENV.delete("KICK_GAIN") : ENV["KICK_GAIN"] = previous
  end

  # ---------------------------------------------------------------- wav map

  # A cycle whose end does not meet its start is a step discontinuity repeating
  # at the fundamental, which is broadband buzz on every note. Every path has to
  # close, and this checks the geometry rather than the audio.
  def test_every_path_closes
    WavMap::PATHS.each do |path|
      start = WavMap.path_point(path, 0.0)
      finish = WavMap.path_point(path, 1.0)

      assert_in_delta start[0], finish[0], 1e-6, "#{path} does not close in x"
      assert_in_delta start[1], finish[1], 1e-6, "#{path} does not close in y"
    end
  end

  def test_every_path_stays_on_the_surface
    WavMap::PATHS.each do |path|
      (0..200).each do |i|
        x, y = WavMap.path_point(path, i / 200.0)

        assert_includes 0.0..1.0, x, "#{path} left the surface in x at t=#{i / 200.0}"
        assert_includes 0.0..1.0, y, "#{path} left the surface in y at t=#{i / 200.0}"
      end
    end
  end

  # ----------------------------------------------------- console stack

  # Every depth has to come out at the level it went in, or A/B-ing the count
  # measures the makeup instead of the sound. A first version of this was 10 dB
  # down at four instances.
  def test_every_stack_depth_declares_a_makeup
    (1..4).each do |n|
      assert Outboard::STACK_DRIVE.key?(n), "no drive for #{n} instance(s)"
      assert Outboard::STACK_MAKEUP.key?(n), "no measured makeup for #{n} instance(s)"
      assert_includes Outboard.console_stack(instances: n), "volume=#{Outboard::STACK_MAKEUP[n]}dB"
    end
  end

  # Past four is unmeasured, and an unmeasured drive is the thing outboard.rb
  # exists not to carry.
  def test_the_stack_clamps_to_what_was_measured
    assert_equal Outboard.console_stack(instances: 4), Outboard.console_stack(instances: 9)
    assert_equal Outboard.console_stack(instances: 1), Outboard.console_stack(instances: 0)
  end

  # ------------------------------------------------------- arrangement

  # The pairing that catches a layer wired to nothing. :lead and :chops were
  # each declared and unread for their whole lives; :harm was applied and
  # undeclared. Both halves have to keep agreeing.
  def test_every_declared_section_layer_is_applied_somewhere
    assert_empty SECTION_LAYERS_DECLARED - SECTION_LAYERS_APPLIED,
                 "declared in a gain table and never applied to a chain"
  end

  def test_the_default_table_leaves_pad_and_texture_flat
    with_env("SECTION_LAYERS" => "1") do
      assert_empty section_layer_windows(:pad, 32, 2.727)
      assert_empty section_layer_windows(:texture, 32, 2.727)
    end
  end

  def test_section_layers_full_gives_pad_and_texture_a_shape
    with_env("SECTION_LAYERS" => "full") do
      refute_empty section_layer_windows(:pad, 32, 2.727)
      refute_empty section_layer_windows(:texture, 32, 2.727)
      # And the drums keep the shape they already had -- `full` adds layers, it
      # does not redraw the ones that were working.
      assert_equal with_env("SECTION_LAYERS" => "1") { section_layer_windows(:drums, 32, 2.727) },
                   section_layer_windows(:drums, 32, 2.727)
    end
  end

# ------------------------------------------------------- arrangement

# Synthetic features with a boundary built in at a known place, so the
# detector is checked against an answer rather than against a plausible
# picture. Two constant timbres, spliced at frame 128.
def two_block_features(length: 256, boundary: 128, bins: 32)
  a = Array.new(bins) { |i| i.even? ? 1.0 : 0.0 }
  b = Array.new(bins) { |i| i.even? ? 0.0 : 1.0 }
  norm = ->(v) { n = Math.sqrt(v.sum { |x| x * x }); v.map { |x| x / n } }
  (0...length).map { |i| norm.call(i < boundary ? a : b) }
end

def test_novelty_peaks_at_a_known_boundary
  curve = Arrangement.novelty(two_block_features, kernel: 16)
  peak = curve.each_with_index.max_by(&:first).last

  assert_in_delta 128, peak, 2, "the peak should land on the splice"
end

# The failure that made the first version of this useless: a relative
# threshold always finds something, so material with NO boundary reported
# four. Uniform features are the null case in its purest form.
def test_uniform_material_yields_no_boundaries
  flat = Array.new(256) { Array.new(32, 1.0 / Math.sqrt(32)) }
  curve = Arrangement.novelty(flat, kernel: 16)

  assert_empty Arrangement.boundaries(curve, seconds_per_frame: 0.5)
end

# The floor is a measured number, not a taste. If it drifts above a real
# boundary the detector goes blind, and it fails silently when it does.
def test_the_noise_floor_still_admits_a_real_boundary
  curve = Arrangement.novelty(two_block_features, kernel: 16)

  assert_operator curve.max, :>, Arrangement::NOISE_FLOOR,
                  "a clean splice must clear the noise floor"
  refute_empty Arrangement.boundaries(curve, seconds_per_frame: 0.5)
end

# Cosine over L2-normalised columns is what makes novelty a comparison of
# spectral SHAPE. If it started responding to level it would become a worse
# copy of the loudness meter and the two instruments would stop disagreeing.
def test_similarity_ignores_level
  quiet = [0.6, 0.8]
  loud = [0.6, 0.8]

  assert_in_delta 1.0, Arrangement.cosine(quiet, loud), 1e-9
  assert_in_delta 0.0, Arrangement.cosine([1.0, 0.0], [0.0, 1.0]), 1e-9
end

# Percentile spread, not min-to-max: one clipped transient or one silent gap
# would otherwise define the answer for the whole track.
def test_loudness_spread_is_robust_to_one_outlier
  normal = (0...100).map { |i| [i.to_f, -20.0 + (i % 5)] }
  with_outlier = normal + [[100.0, -70.0]]

  assert_in_delta Arrangement.spread(normal)[:spread],
                  Arrangement.spread(with_outlier)[:spread], 1.0
end

  # The defect that made this module confidently wrong, pinned.
  #
  # COLUMNS was fixed at 512 and the frame duration floated with the file: an
  # 87-second render measured at 0.17 s per frame and a 290-second record at
  # 0.57 s. Novelty at an eighth-note is a different question from novelty at a
  # phrase, so the two were never comparable -- and the difference read as a real
  # and dramatic musical finding. Three hypotheses were built and tested against
  # it before anyone ran the duration control.
  #
  # Checked over the range where the column clamps do not bind, which is
  # everything from MIN_COLUMNS * FRAME_SEC (32 s) to MAX_COLUMNS * FRAME_SEC
  # (17 minutes). Outside it the frame necessarily stretches or shrinks, and the
  # test below pins that as the deliberate exception rather than leaving it to
  # look like the same bug coming back.
  def test_seconds_per_frame_is_constant_across_durations
    [40.0, 87.0, 290.0, 600.0].each do |duration|
      spf = duration / Arrangement.columns_for(duration)

      assert_in_delta Arrangement::FRAME_SEC, spf, 0.02,
                      "#{duration}s resolves at #{spf.round(3)}s per frame — a frame must be a fixed " \
                      "DURATION, or two files of different lengths are asked different questions"
    end
  end

  # The clamps are what would let that invariant hold everywhere except where it
  # matters, so they are stated rather than assumed. A two-hour file at
  # half-second frames would want 14,400 columns.
  def test_column_count_is_bounded_without_breaking_ordinary_lengths
    assert_equal Arrangement::MAX_COLUMNS, Arrangement.columns_for(7200.0)
    assert_equal Arrangement::MIN_COLUMNS, Arrangement.columns_for(1.0)
    assert_equal 174, Arrangement.columns_for(87.0)
  end

  # The floor was re-derived when the frame changed, and the two have to stay in
  # step: a floor measured on one instrument means nothing on another. The old
  # instrument separated null from real by 4.25x and wanted 0.015; this one
  # separates them by 15x and wants 0.005.
  def test_the_noise_floor_matches_the_instrument_it_was_measured_on
    assert_in_delta 0.005, Arrangement::NOISE_FLOOR, 1e-9,
                    "NOISE_FLOOR was measured at FRAME_SEC #{Arrangement::FRAME_SEC}; " \
                    "changing the frame requires re-measuring the null cases"
  end

  # ------------------------------------------------------------- form fit

  # A form is a cycle, so a 32-bar map over a 128-bar render is four copies of
  # itself -- four intros, four outros, an "intro" at bars 32, 64 and 96. That is
  # a loop of a form rather than the shape of a piece, and it is why dilla could
  # not express what the records it is measured against do: one arc, each part
  # happening once, across four or five minutes.
  def test_form_fit_stretches_the_form_over_the_track_instead_of_repeating_it
    with_env("FORM" => "soul_32", "FORM_FIT" => "1") do
      forget_form_map!
      kinds = (0...128).map { |b| dilla_section(b, 128) }

      assert_equal 1, runs_of(kinds).count { |kind, _| kind == :intro },
                   "a stretched form has one intro; a cycled one has four"
      assert_equal 4, runs_of(kinds).length - 1
    end
  end

  def test_the_default_still_cycles
    with_env("FORM" => "soul_32", "FORM_FIT" => nil) do
      forget_form_map!

      assert_equal 4, runs_of((0...128).map { |b| dilla_section(b, 128) }).count { |kind, _| kind == :intro }
    end
  end

  # When the map already spans the track there is nothing to stretch, and the two
  # paths have to agree exactly -- otherwise turning the flag on would silently
  # change every 32-bar render that already used a 32-bar form.
  def test_form_fit_changes_nothing_when_the_map_already_spans_the_track
    cycled = with_env("FORM" => "soul_32", "FORM_FIT" => nil) do
      forget_form_map!
      (0...32).map { |b| dilla_section(b, 32) }
    end
    fitted = with_env("FORM" => "soul_32", "FORM_FIT" => "1") do
      forget_form_map!
      (0...32).map { |b| dilla_section(b, 32) }
    end

    assert_equal cycled, fitted
  end

  # Every bar has to belong to a section. Rounding each scaled length
  # independently leaves a gap, and a bar that matches nothing falls through to
  # the legacy map -- a stray `main` after the outro, very hard to see.
  def test_every_bar_belongs_to_a_section_at_any_length
    with_env("FORM" => "soul_32", "FORM_FIT" => "1") do
      [17, 32, 33, 64, 100, 128, 257].each do |bars|
        forget_form_map!
        kinds = (0...bars).map { |b| dilla_section(b, bars) }

        assert_equal bars, kinds.compact.length, "#{bars} bars left a bar with no section"
        assert_equal :outro, kinds.last, "#{bars} bars did not end on the form's last section"
      end
    end
  end

  # --------------------------------------------------------- voice stack

  # P_4L's actual move: one macro position becomes n DIFFERENT positions. If the
  # voices all landed on the same value the stack would be one voice rendered n
  # times, which is louder and nothing else.
  def test_the_stack_gives_every_voice_its_own_macro_position
    plan = VoiceStack.plan(voices: 5, macro: 0.5, variation: 0.4)

    assert_equal 5, plan.length
    assert_equal 5, plan.map(&:macro).uniq.length
  end

  # Variation 0 is the degenerate case and has to collapse cleanly, or "no
  # variation" would still wobble.
  def test_zero_variation_collapses_the_stack_to_one_position
    plan = VoiceStack.plan(voices: 4, macro: 0.7, variation: 0.0)

    assert_equal [0.7], plan.map(&:macro).uniq
  end

  # The spread has to be the spread that was ASKED for, whatever the seed.
  # Independent draws cluster: measured across five seeds at amount 0.25 the span
  # came out 0.360, 0.288, 0.327, 0.199 and 0.342 -- between a third and two
  # thirds of the request, depending on luck. Stratified draws fix that, and this
  # is the test that would have caught it.
  def test_the_spread_is_the_amount_that_was_requested
    spans = [1, 42, 4242, 777, 999].map do |seed|
      values = DillaMacros.spread(0.5, amount: 0.25, count: 4, seed:)

      assert_in_delta 0.5, values.sum / values.length, 1e-9, "seed #{seed} moved the centre"
      values.max - values.min
    end

    assert_operator spans.max - spans.min, :<, 0.12,
                    "the delivered spread swings with the seed: #{spans.map { |s| s.round(3) }.inspect}"
    assert_operator spans.min, :>, 0.3, "the requested amount is not being delivered"
  end

  # Key tracking: a voice an octave up needs its cutoff an octave up, or the top
  # of a stack goes dull because a fixed cutoff removes a larger share of a
  # higher note's harmonics.
  def test_key_tracking_follows_the_register
    full = VoiceStack.plan(voices: 3, detune_mode: :octaves, key_track: 1.0)
    none = VoiceStack.plan(voices: 3, detune_mode: :octaves, key_track: 0.0)
    up = full.find { |v| v.semitones == 12 }

    assert_in_delta 2.0, up.cutoff_scale, 1e-6, "an octave up should double the cutoff at full tracking"
    assert_equal [1.0], none.map(&:cutoff_scale).uniq, "no tracking means no scaling"
  end

  # Transposition must move pitch and nothing else -- same count, same times.
  def test_transposing_a_voice_keeps_the_rhythm
    events = (0...8).map { |i| [i * 0.25, 0.8, { hz: [220.0] }, 0.2] }
    voice = VoiceStack.plan(voices: 2, detune_mode: :octaves).last
    moved = VoiceStack.transpose(events, voice)

    assert_equal events.map(&:first), moved.map(&:first)
    assert_equal events.length, moved.length
    refute_in_delta 220.0, moved.first[2][:hz].first, 1.0
  end

  # ------------------------------------------------------- low-pass gate

  # The whole claim of an LPG, as arithmetic on the control signal: as it closes,
  # the cutoff falls WITH it. A VCA leaves cutoff alone, a filter leaves gain
  # alone, and this is the coupling that makes a note sound struck.
  def test_the_gate_darkens_as_it_closes
    span = LowPassGate::OPEN_HZ / LowPassGate::CLOSED_HZ
    open_hz = LowPassGate::CLOSED_HZ * (span**1.0)
    half_hz = LowPassGate::CLOSED_HZ * (span**0.5)
    shut_hz = LowPassGate::CLOSED_HZ * (span**0.0)

    assert_in_delta LowPassGate::OPEN_HZ, open_hz, 1e-6
    assert_in_delta LowPassGate::CLOSED_HZ, shut_hz, 1e-6
    assert_operator half_hz, :<, open_hz
    assert_operator half_hz, :>, shut_hz
    # Geometric, not linear. The ear hears cutoff in octaves, and a linear sweep
    # spends most of its travel where there is nothing left to hear.
    refute_in_delta (open_hz + shut_hz) / 2.0, half_hz, 100.0
  end

  # A signal in must produce a signal out. The first version rounded a -1..1
  # float signal to integers and silenced it completely: the DSP model was
  # correct and the output was digital silence.
  def test_the_gate_passes_signal
    samples = (0...4410).map { |i| 0.6 * Math.sin(2 * Math::PI * 220 * i / 44_100.0) }
    out = LowPassGate.process(samples, rate: 44_100)

    assert_equal samples.length, out.length
    assert_operator out.map(&:abs).max, :>, 0.01, "the gate silenced a steady tone"
    assert(out.any? { |v| v != v.round }, "output must be floats; rounding silences a -1..1 signal")
  end

  # blend 0 is a plain VCA and must not filter, which is what makes the control
  # a real choice rather than decoration.
  def test_blend_zero_leaves_the_tone_alone
    samples = (0...2205).map { |i| 0.5 * Math.sin(2 * Math::PI * 6000 * i / 44_100.0) }
    vca = LowPassGate.process(samples, rate: 44_100, blend: 0.0)
    gated = LowPassGate.process(samples, rate: 44_100, blend: 1.0)

    assert_operator vca.map(&:abs).max, :>, gated.map(&:abs).max,
                    "at 6 kHz a closed gate must remove more than a VCA does"
  end

# ------------------------------------------------------- device reach

# A device no renderer can call is a device that cannot change a render.
#
# This is dillas most-repeated defect and the reason `dilla audit` exists: 24
# pad voices, 209 of 250 progressions, the chopped sample loops and a pad whose
# effect chain had never once opened all shipped complete, correct and
# unreachable. Six new devices arrived the same way -- built, tested, and
# callable only from the command line.
#
# So reach is a ratchet. A module here has to be named by something that is not
# itself, not its own CLI command, and not a test: a renderer, a bus builder, a
# scheduler -- code a render actually runs.
#
# The path is the module's OWN file, excluded from the search so a module is
# never counted as calling itself. Keeping it right matters more than it looks:
# after the merge into devices.rb these still named copy_machine.rb,
# midi_devices.rb, wav_map.rb and macros.rb, none of which exist any more -- so
# nothing was excluded, devices.rb counted as an external caller of its own
# modules, and the ratchet passed for every one of them without checking
# anything. A guard keyed on a stale path is a guard that has stopped guarding.
DEVICE_MODULES = {
  "CopyMachine" => "lib/devices.rb",
  "MidiDevices" => "lib/devices.rb",
  "WavMap" => "lib/devices.rb",
  "LowPassGate" => "lib/devices.rb",
  "VoiceStack" => "lib/devices.rb",
  "DillaModulation" => "lib/modulation.rb",
  "DillaMacros" => "lib/knobs.rb",
}.freeze

# device_cmds is the CLI surface and arrangement.rb is an analysis tool; being
# named by either proves nothing about whether a RENDER can reach the device.
REACH_EXCLUDED = %w[device_cmds.rb arrangement.rb].freeze

def test_every_device_is_reachable_from_a_render
  unreachable = DEVICE_MODULES.reject do |mod, own|
    Dir[File.join(DillaSources.root, "lib", "**", "*.rb")].any? do |path|
      next false if File.expand_path(path) == File.expand_path(File.join(DillaSources.root, own))
      next false if REACH_EXCLUDED.include?(File.basename(path))

      # `.` or `::`, because MidiDevices is reached as MidiDevices::Bag. A
      # ratchet matching only a dot reports a wired module as unwired, which is
      # the same failure as the one it exists to catch, pointing the other way.
      File.read(path).gsub(/^\s*#(?!\{).*$/, "").match?(/\b#{Regexp.escape(mod)}(\.|::)/)
    end
  end

  assert_empty unreachable.keys,
               "built and wired to nothing — no renderer, bus or scheduler calls these, " \
               "so no render can reach them however well they work"
end

  def runs_of(kinds)
    kinds.chunk_while { |a, b| a == b }.map { |r| [r.first, r.length] }
  end

  private

  def forget_form_map!
    return unless instance_variable_defined?(:@resolve_form_map)

    remove_instance_variable(:@resolve_form_map)
  end

  def with_env(pairs)
    previous = pairs.keys.to_h { |k| [k, ENV.fetch(k, nil)] }
    pairs.each { |k, v| ENV[k] = v }
    yield
  ensure
    previous.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end
end
