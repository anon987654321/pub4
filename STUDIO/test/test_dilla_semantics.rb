# frozen_string_literal: true

require_relative "dilla_helper"

# DillaSemantics and the renderer that plays it.
#
# What would break silently: a swing that reaches the kick, an arrangement
# section that adds what the full state lacks, a figure that stops cycling on its
# own length, a profile knob nothing reads, and a rumble that is a sine rather
# than the kick's own tail. Each is pinned here; none shows up as an error.
class TestDillaSemantics < Minitest::Test
  S = DillaSemantics

  def setup
    @env_before = ENV.to_h
  end

  def teardown
    (ENV.keys - @env_before.keys).each { |k| ENV.delete(k) }
    @env_before.each { |k, v| ENV[k] = v unless ENV[k] == v }
  end

  def with_axes(name, **axes)
    base = S.profile(name)
    base.merge(axes: base[:axes].merge(axes))
  end

  def test_every_profile_states_every_axis_on_the_unit_range
    S::PROFILES.each do |name, profile|
      assert_equal S::AXES.sort, profile[:axes].keys.sort, "#{name} leaves an axis undescribed"
      profile[:axes].each { |axis, value| assert_includes 0.0..1.0, value, "#{name}.#{axis}" }
      assert_includes S::LOW_ENDS, profile[:low_end]
      assert_empty profile[:elements] - S::ELEMENTS.keys, "#{name} names an element nothing plays"
      assert_equal %i[amp_decay body_hz click_ms drive sweep_decay sweep_hz], profile[:kick].keys.sort
    end
  end

  def test_an_unknown_profile_names_the_ones_that_exist
    error = assert_raises(ArgumentError) { S.profile("gabber") }
    assert_match(/basic_channel/, error.message)
  end

  # Swing is not techno; the relationship between layers is. The kick holds the
  # clock while detroit's off-sixteenth hats land late, and basic_channel's do not
  # move at all.
  def test_swing_shifts_the_hats_and_never_the_kick
    detroit = S.profile(:detroit)
    beat = 60.0 / detroit[:bpm]
    swing = 0.5 + (detroit[:axes][:microtiming] * 0.12)

    assert_in_delta 0.0, S.timing_offset(detroit, :kick, 1, beat), 1e-9
    assert_in_delta ((2 * swing) - 1) * beat / 4, S.timing_offset(detroit, :hat, 3, beat), 1e-9
    assert_in_delta 0.0, S.timing_offset(detroit, :hat, 2, beat), 1e-9
    assert_in_delta 0.0, S.timing_offset(S.profile(:basic_channel), :hat, 3, beat), 1e-9
  end

  def test_the_pocket_profile_drags_the_clap_by_the_dilla_ticks
    pocket = S.profile(:dilla_pocket)
    beat = 60.0 / pocket[:bpm]
    ticks = DillaGroove::GROOVE_FEELS[:dilla_drag][:clap]

    assert_in_delta ticks * pocket[:axes][:microtiming] * beat / 96.0, S.timing_offset(pocket, :clap, 4, beat), 1e-9
  end

  # Each element comes round on its own length, so two-, three- and four-bar
  # figures only agree every twelve bars.
  def test_each_element_cycles_on_its_own_length
    still = with_axes(:detroit, mutation: 0.0, sparsity: 0.0)
    figure = ->(element, bar) { S.figure(still, element, bar, seed: 7).map(&:first) }

    assert_equal figure.call(:perc_a, 0), figure.call(:perc_a, 2)
    refute_equal figure.call(:perc_a, 0), figure.call(:perc_a, 1)
    assert_equal figure.call(:stab, 1), figure.call(:stab, 5)
    refute_equal figure.call(:stab, 1), figure.call(:stab, 2)
    refute_equal figure.call(:perc_b, 0), figure.call(:perc_b, 1), "the polymeter reset at the bar line"
  end

  # A mutation is a new state that persists, not a fill.
  def test_a_mutation_holds_for_its_window_and_changes_after_it
    restless = with_axes(:hardgroove, mutation: 1.0, persistence: 0.0)
    window = 4
    inside = (0...window).map { |bar| S.mutation(restless, :hat, bar, 11) }

    assert_equal [inside.first], inside.uniq
    changes = (1..12).map { |w| S.mutation(restless, :hat, w * window, 11) }
    refute_equal [inside.first], changes.uniq, "twelve windows drew the same step every time"
    assert_empty S.mutation(with_axes(:hardgroove, mutation: 0.0), :hat, 3, 11)
  end

  def test_sparsity_takes_the_hit_before_an_accent
    steps = [2, 3, 6, 7, 10, 11, 14, 15]
    dense = S.sparse(with_axes(:detroit, sparsity: 0.0), :hat, steps, Random.new(1))
    thinned = (0...32).map { |bar| S.sparse(with_axes(:detroit, sparsity: 1.0), :hat, steps, Random.new(bar)) }

    assert_equal steps, dense
    assert(thinned.any? { |s| (steps - s).any? { |gone| [3, 7, 11, 15].include?(gone) } })
    assert(thinned.all? { |s| (steps - s).none? { |gone| [2, 6, 10, 14].include?(gone) } }, "only pre-accent hits go")
  end

  # The busiest state is the definition; no section holds more than it.
  def test_every_section_is_the_full_state_reduced_or_transformed
    S::PROFILES.each do |name, profile|
      full = S.section_state(profile, :full)
      assert(full.values.all? { |s| s[:gain] == 1.0 && s[:transform].nil? }, "#{name} full is not full")

      S::SECTION_MOVES.each_key do |section|
        state = S.section_state(profile, section)
        assert_equal profile[:elements].sort, state.keys.sort, "#{name}/#{section} added or lost an element"
        assert(state.values.all? { |s| s[:gain] <= 1.0 }, "#{name}/#{section} accumulates")
      end
    end
    strip = S.section_state(S.profile(:detroit), :strip)
    assert_operator strip[:clap][:gain], :<, 1.0
    assert_operator S.section_state(S.profile(:basic_channel), :lift)[:low][:gain], :>, 0.0,
                    "low contrast should leave a removed element faintly present"
  end

  def test_a_short_render_is_the_peak_and_a_long_one_holds_it
    assert_equal [:full], S.sections(16)
    (1..12).each { |n| assert_includes S.sections(n * 16), :full, "#{n} sections" }
    assert_equal 12, S.sections(12 * 16).length
  end

  def test_energy_is_a_vector_measured_from_the_state
    detroit = S.profile(:detroit)
    full = S.energy(detroit, :full)
    strip = S.energy(detroit, :strip)
    damage = S.energy(detroit, :damage, previous: full)

    assert_equal S::ENERGY.sort, full.keys.sort
    assert_operator full[:density], :>, strip[:density]
    assert_operator full[:spectral_width], :>=, strip[:spectral_width]
    assert_equal 0.0, full[:contrast]
    assert_operator damage[:contrast], :>, 0.0
    assert_operator damage[:harmonic_density], :>, full[:harmonic_density]
  end

  def test_dropouts_fall_only_on_a_section_edge
    tense = with_axes(:industrial, tension: 1.0)

    assert(S.dropout_bar?(tense, 15, 3))
    refute((0..14).any? { |bar| S.dropout_bar?(tense, bar, 3) })
    refute(S.dropout_bar?(with_axes(:industrial, tension: 0.0), 15, 3))
  end

  def test_profiles_reach_hate_and_industrial_through_knobs_they_read
    require File.expand_path("../dilla/lib/ledger", __dir__)
    env = S.engine_env(S.profile(:basic_channel))

    assert_equal "0", env["HATE_DILLA"]
    assert_equal "1", env["HATE_TUNNEL"]
    assert_equal "1", S.engine_env(S.profile(:industrial))["HATE_DFAM_HEAVY"]
    assert_equal "1", S.engine_env(S.profile(:hardgroove))["HATE_INTRICATE"]
    assert_equal "128", S.engine_env(S.profile(:detroit))["IBPM"]
    env.each_key { |knob| refute_nil DillaKnobs[knob], "#{knob} is a knob nothing reads" }
  end

  def test_a_hand_set_knob_beats_the_profile
    target = { "HATE_TUNNEL" => "0" }
    applied = S.apply_env!({ "HATE_TUNNEL" => "1", "HATE_WEIRD" => "1" }, target)

    assert_equal({ "HATE_WEIRD" => "1" }, applied)
    assert_equal "0", target["HATE_TUNNEL"]
  end

  # The body takes the drive and the click does not.
  def test_the_kick_drives_its_body_and_leaves_its_click_clean
    voice = S.profile(:industrial)[:kick]
    clean_click, clean_body = TechnoVoices.kick(voice.merge(drive: 0.0))
    dirty_click, dirty_body = TechnoVoices.kick(voice)

    assert_equal clean_click, dirty_click
    crest = ->(s) { s.map(&:abs).max / Math.sqrt(s.sum { |x| x * x } / s.length) }
    assert_operator crest.call(dirty_body), :<, crest.call(clean_body) * 0.9, "the drive added nothing"
  end

  def test_the_kick_pitch_falls_through_the_note
    _, body = TechnoVoices.kick(S.profile(:industrial)[:kick].merge(drive: 0.0))
    crossings = ->(range) { body[range].each_cons(2).count { |a, b| a.negative? != b.negative? } }

    assert_operator crossings.call(0...2205), :>, crossings.call(8820...11_025)
  end

  # Rumble is the kick's tail, so a bus with no kick has no rumble.
  def test_rumble_grows_from_the_kick_and_nothing_else
    silent = Array.new(22_050, 0.0)
    assert(TechnoVoices.rumble(silent, feedback: 0.8, dirt: 0.5).all?(&:zero?))

    kick_bus = Array.new(44_100, 0.0)
    TechnoVoices.place!(kick_bus, TechnoVoices.kick(S.profile(:basic_channel)[:kick]).last, 0, 1.0)
    rumble = TechnoVoices.rumble(kick_bus, feedback: 0.8, dirt: 0.5)
    tail = rumble[22_050..].sum(&:abs)
    kick_tail = kick_bus[22_050..].sum(&:abs)
    assert_operator tail, :>, kick_tail, "the rumble should sustain past the kick"
  end

  def test_an_fm_burst_opens_rich_and_settles
    burst = TechnoVoices.fm_burst(hz: 300.0, ratio: 1.5, index: 4.0, velocity: 1.0, length: 0.2)
    pure = TechnoVoices.fm_burst(hz: 300.0, ratio: 1.5, index: 0.0, velocity: 1.0, length: 0.2)
    # Relative to the note's own level at that moment, or the amplitude decay
    # alone would make the late window look settled.
    gap = ->(range) { range.sum { |i| (burst[i] - pure[i]).abs } / [range.sum { |i| pure[i].abs }, 1e-9].max }

    assert_operator gap.call(0...220), :>, gap.call(4410...4630) * 4
  end

  def test_resampling_recuts_the_audio_the_same_way_for_the_same_seed
    source = Array.new(8000) { |i| Math.sin(i * 0.05) * (i % 400 < 50 ? 1.0 : 0.2) }
    once = TechnoVoices.resample(source.dup, passes: 2, slice: 500, rng: Random.new(5))
    again = TechnoVoices.resample(source.dup, passes: 2, slice: 500, rng: Random.new(5))

    assert_equal once, again
    refute_equal source, once
    assert_in_delta source.length, once.length, 500
    assert_equal source, TechnoVoices.resample(source, passes: 0, slice: 500, rng: Random.new(5))
  end

  def test_the_plan_plays_only_the_profile_and_honours_its_silences
    pocket = SemanticTechno.new(S.profile(:dilla_pocket), bars: 16, seed: 9)
    assert_empty pocket.events.map { |e| e[:element] }.uniq - S.profile(:dilla_pocket)[:elements]
    assert(pocket.events.none? { |e| e[:element] == :low }, "kick_tail has no separate low part")

    tense = SemanticTechno.new(with_axes(:industrial, tension: 1.0), bars: 16, seed: 9)
    late_kicks = tense.events.select { |e| e[:element] == :kick && e[:bar] == 15 && e[:step] >= 8 }
    assert_empty late_kicks, "the dropout bar kept its kick"
  end

  def test_a_render_is_stereo_audio_of_the_planned_length
    render = SemanticTechno.new(S.profile(:basic_channel), bars: 4, seed: 3)
    left, right = render.render

    assert_equal render.frames, left.length
    assert_equal left.length, right.length
    rms = Math.sqrt(left.sum { |x| x * x } / left.length)
    assert_operator rms, :>, 0.05, "the render is near silence"
    refute_equal left, right
  end

  # One hit, two figures: the left side repeats on the dotted eighth and the
  # right on the quarter, and the feedback axis decides how long they survive.
  def test_delay_writes_counterpoint_and_feedback_sets_its_generations
    beat = (60.0 / S.profile(:detroit)[:bpm] * TechnoVoices::RATE).round
    tails = [0.0, 1.0].to_h do |feedback|
      render = SemanticTechno.new(with_axes(:detroit, feedback:), bars: 4, seed: 1)
      space = Array.new(2) { Array.new(beat * 12, 0.0).tap { |side| side[0] = 1.0 } }
      render.send(:echo!, space)
      first_echo = space.map { |side| ((beat / 2)...(beat * 3 / 2)).max_by { |i| side[i].abs } }
      assert_in_delta beat * 0.75, first_echo[0], beat * 0.05, "left is not on the dotted eighth"
      assert_in_delta beat, first_echo[1], beat * 0.05, "right is not on the quarter"
      [feedback, space[1][(beat * 6)..].sum(&:abs)]
    end
    assert_operator tails[1.0], :>, tails[0.0] * 1.5, "the feedback axis did not lengthen the tail"
  end
end
