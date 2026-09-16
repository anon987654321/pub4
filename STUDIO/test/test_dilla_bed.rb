# frozen_string_literal: true

require_relative "dilla_helper"
require "open3"

# The bed is dilla's render: a bare `ruby dilla.rb` plays the catalogue through
# it and `ruby dilla.rb bed` plays it under the narration. These pin what the
# operator asked of it and what is easiest to lose in an edit: every piece of
# the catalogue voiced, nothing played that the engine did not synthesise, no
# setting without a reader, and a rendered piece that lands where it should.
class TestDillaBed < Minitest::Test
  DILLA_SOURCE = File.read(File.expand_path("../dilla/dilla.rb", __dir__))
  BED_SOURCE = DILLA_SOURCE[/^module Bed\n.*?^end\n/m]
  # data/bed.yml declares the bed and the piece, and module Composition reads the piece.
  READERS = BED_SOURCE + DILLA_SOURCE[/^module Composition\n.*?^end\n/m]

  # The catalogue is seven recordings and twelve improvisations, and a bare
  # invoke plays exactly that. A cut to four was made once and reversed.
  def test_the_catalogue_is_seven_verified_and_twelve_improvised
    sizes = demo_catalog_sizes

    assert_equal 7, sizes[:verified]
    assert_equal 12, sizes[:improvised]
    assert_equal VERIFIED_PROGRESSION_SLOTS.map(&:to_sym), demo_curated_order.first(7), "the recordings come first"
  end

  # Every chord of every piece voices. The verified rows spell chords the bed's
  # own table reads; the improvised ones spell quartal stacks and bare triad
  # words, which the engine's resolver turns into frequencies.
  def test_every_catalogue_chord_voices
    unvoiced = demo_curated_order.flat_map do |name|
      Array(CHORD_PROGRESSIONS[name]).reject { |symbol| Bed.parse_chord(symbol) }.map { |symbol| "#{name}:#{symbol}" }
    end

    assert_empty unvoiced
  end

  # A symbol the table does not spell exactly is not guessed at: "dimimp"
  # begins with the empty suffix, and matched by prefix a diminished chord came
  # back major. The improvisations are drawn per seed, so the test finds a
  # diminished symbol in whatever the catalogue holds now.
  def test_an_unknown_quality_goes_to_the_resolver_not_to_a_major_triad
    symbol = demo_curated_order.flat_map { |name| Array(CHORD_PROGRESSIONS[name]) }.find { |s| s.to_s.include?("dim") }
    skip "no diminished chord in this draw of the improvisations" unless symbol

    chord = Bed.parse_chord(symbol)
    assert_includes chord.intervals, 6, "#{symbol} lost its diminished fifth"
    refute_includes chord.intervals, 4, "#{symbol} came back with a major third"
  end

  # dilla synthesises every sound it plays. The bed's families are oscillators
  # and the kit is the engine's own; a soundfont is somebody else's instrument.
  def test_the_bed_plays_nothing_it_did_not_synthesise
    refute_match(/fluidsynth|\.sf2/, BED_SOURCE)
    assert(Bed::FAMILIES.values.all? { |spec| spec["source"] == "oscillator" })
    assert_includes BED_SOURCE, "ensure_drum_kit!", "the kit must be generated before the drummer plays it"
  end

  # A key in data/bed.yml with no reader is a decision that does nothing. These
  # three describe how the declaration was made rather than what a render does.
  DESCRIPTIVE_KEYS = %w[records reference progressions].freeze

  def test_every_declared_setting_has_a_reader
    unread = Bed::BED.keys.reject do |key|
      DESCRIPTIVE_KEYS.include?(key) || READERS.match?(/BED\.fetch\("#{key}"\)|BED\.dig\("#{key}"|BED\["#{key}"\]/)
    end

    assert_empty unread
  end

  # Voice leading keeps the upper structure inside two octaves and moves it by
  # small steps: a chord that jumps its whole voicing is a sequence of chords,
  # not a progression.
  def test_a_progression_is_voice_led
    srand(11)
    chords = CHORD_PROGRESSIONS[:maj7_minor_cycle].map { |symbol| Bed.parse_chord(symbol) }
    progression = Bed::Progression.new(name: "maj7_minor_cycle", chords:)
    voiced = Bed.voice_pass([progression], Bed.deal_instruments(1))
    uppers = voiced.map { |chord| chord.notes.drop(1) }

    uppers.each { |notes| assert_operator notes.max - notes.min, :<=, Bed::MAX_SPAN }
    moves = uppers.each_cons(2).map { |a, b| (a.sum.to_f / a.size - b.sum.to_f / b.size).abs }
    assert_operator moves.max, :<=, 7.0, "a voicing's centre moved more than a fifth between chords"
  end

  # One piece through the bed: its length is its bars, its loudness is the
  # target, and its true peak is under the ceiling.
  def test_a_catalogue_piece_renders_to_length_loudness_and_peak
    skip "ffmpeg not on PATH" unless system("which", "ffmpeg", out: File::NULL, err: File::NULL)

    out = File.join(Dir.tmpdir, "dilla_bed_piece_#{Process.pid}.wav")
    Bed.render_track!("minor_half_step_pair", out, 5)
    duration = Open3.capture2("ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", out).first.to_f
    log = Open3.capture2e("ffmpeg", "-hide_banner", "-nostats", "-i", out, "-af", "ebur128=peak=true", "-f", "null", "-").first
    reading = FfmpegProbe.ebur128_summary(log)

    # Within a few frames per bar: the chop and the mix join files cut at sample
    # boundaries, and eight of them round down by a quarter of a second.
    assert_in_delta 4 * Bed::CHORD_BARS, duration, 0.4, "a two-chord vamp is stated to four chords"
    assert_in_delta Float(Bed::LOUDNESS.fetch("lufs")), reading[:i], 0.7
    assert_operator reading[:tp], :<=, Float(Bed::LOUDNESS.fetch("true_peak_db"))
  ensure
    FileUtils.rm_f(out) if out
  end
end

# demo.wav is one piece, and these pin what the operator asked of it on
# 2026-09-15: about six minutes, the drums every bar with a kick dropout of a bar
# or two at most, the parts answering each other, and every move an event
# transform the data names.
class TestDillaComposition < Minitest::Test
  C = Composition
  E = DillaEvents
  SOURCE = File.read(File.expand_path("../dilla/dilla.rb", __dir__))

  def test_a_bare_invoke_renders_the_piece
    assert_match(/if cmd\.nil\?\n(?:\s*#[^\n]*\n)*\s*Composition\.demo!/, SOURCE)
  end

  def test_the_piece_is_about_six_minutes_in_twelve_sections
    assert_equal 12, C::SECTIONS.size
    assert_in_delta 360, C.seconds, 30
  end

  # A kick sounds from the kit or from the HATE layer's own kick, and never goes
  # missing for more than two bars running.
  def test_the_pulse_is_never_gone_for_more_than_two_bars
    srand(5)
    chords, = C.harmony
    lead = C.lead_plan(chords, Random.new(5))
    pulse = (0...C.bars).map do |bar|
      C.drum_events(bar, lead[bar], Random.new(bar)).any? { |event| event.pitch == C::GM[:kick] } ||
        C.hate_profile(C::BAR_SECTIONS[bar]).fetch(:elements).include?(:kick)
    end
    gaps = pulse.chunk_while { |a, b| a == b }.reject(&:first).map(&:size)

    assert_operator gaps.max.to_i, :<=, 2
    assert_operator gaps.size, :>=, 2, "the kick never drops out to expose the harmony"
  end

  def test_every_section_plays_drums
    C::SECTIONS.each do |section|
      refute_empty section.fetch("voices"), section["name"]
      assert_operator section.fetch("gains_db").fetch("kit"), :>, C::SILENT_DB, section["name"]
      assert_operator section.fetch("density"), :>, 0.0, section["name"]
    end
  end

  def test_every_transform_the_data_names_exists
    named = C::SECTIONS.flat_map { |section| section.fetch("drums") + section.fetch("lead") }.uniq

    assert_empty named - C::TRANSFORMS.keys
    assert_equal C::TRANSFORMS.keys.sort, C::FORM.fetch("transforms").keys.sort
  end

  # The motif is the sounding chord's own tones wherever it is stated plainly.
  def test_the_stated_motif_is_made_of_the_chord_under_it
    srand(8)
    chords, = C.harmony
    lead = C.lead_plan(chords, Random.new(8))
    stated = (0...C.bars).select { |bar| C::BAR_SECTIONS[bar].fetch("lead").empty? && lead[bar].any? }

    refute_empty stated
    stated.each do |bar|
      tones = C.chord_at(chords, bar).notes.drop(1)
      lead[bar].each { |note| assert_includes tones, note.pitch }
    end
  end

  def test_the_mirrored_harmony_keeps_the_bass_and_moves_the_upper_voices
    chord = Bed::PassChord.new(notes: [38, 60, 65, 69, 72], family: :rhodes, patch: nil, program: nil)
    turned = C.mirror(chord, 2)

    assert_equal 38, turned.notes.first
    refute_equal chord.notes.drop(1), turned.notes.drop(1)
  end

  # The mirrored section is heard: its chords hold tones the progression at home
  # never plays.
  def test_the_mirrored_section_plays_harmony_the_home_sections_do_not
    srand(13)
    chords, = C.harmony
    slots = chords.each_index.group_by { |slot| C::BAR_SECTIONS[slot * Bed::BARS_PER_CHORD]["harmony"] == "mirrored" }
    classes = ->(indexes) { indexes.flat_map { |slot| chords[slot].notes.drop(1).map { |note| note % 12 } }.uniq }

    refute_empty classes.call(slots.fetch(true)) - classes.call(slots.fetch(false))
  end

  def test_the_hate_layer_takes_its_low_end_only_where_the_bass_is_silent
    section = C::SECTIONS.find { |s| s.dig("hate", "profile") == "industrial" }
    with_low = section.merge("hate" => { "profile" => "industrial", "elements" => %w[kick low] })

    refute_includes C.hate_profile(with_low).fetch(:elements), :low
    silent = with_low.merge("gains_db" => with_low.fetch("gains_db").merge("bass" => C::SILENT_DB))
    assert_includes C.hate_profile(silent).fetch(:elements), :low
    assert_equal Bed::BPM, C.hate_profile(silent).fetch(:bpm)
  end

  def note(pitch, at, duration = 0.5) = E::Event.note(pitch:, at:, duration:)

  def test_reverse_mirrors_time_within_the_span
    reversed = E.reverse([note(60, 0.0), note(62, 1.0)], 2.0)

    assert_equal [[62, 0.5], [60, 1.5]], reversed.map { |event| [event.pitch, event.at] }
  end

  def test_ratchet_strikes_a_note_inside_its_own_length
    hits = E.ratchet([note(60, 1.0, 0.3)], 3)

    assert_equal [1.0, 1.1, 1.2], hits.map { |event| event.at.round(3) }
    assert_operator hits.last.velocity, :<, hits.first.velocity
  end

  def test_invert_and_transpose_move_pitch_only
    assert_equal [64, 60], E.invert([note(60, 0.0), note(64, 0.5)], 62).map(&:pitch)
    assert_equal [72], E.transpose([note(60, 0.25)], 12).map(&:pitch)
  end

  def test_stutter_repeats_the_first_slice_over_what_it_covered
    played = E.stutter([note(60, 0.0), note(62, 0.3), note(64, 1.0)], 0.25, 3)

    assert_equal [[60, 0.0], [60, 0.25], [60, 0.5], [64, 1.0]], played.map { |event| [event.pitch, event.at] }
  end

  def test_a_sample_is_slowed_never_sped_up
    slowed = E.resample([note(60, 1.0)], 0.5).first

    assert_equal [2.0, 1.0, 48.0], [slowed.at, slowed.duration, slowed.pitch]
    assert_raises(ArgumentError) { E.resample([note(60, 1.0)], 2.0) }
  end

  def test_probability_decides_which_notes_play
    events = Array.new(400) { |index| note(60, index * 0.01) }
    kept = E.realize(E.probabilize(events, 0.25), Random.new(1)).size

    assert_in_delta 100, kept, 30
    assert_equal 400, E.realize(events, Random.new(1)).size
  end
end
