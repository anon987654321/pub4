# frozen_string_literal: true

require_relative "dilla_helper"
require "open3"

# The bed is dilla's render: a bare `ruby dilla.rb` plays the catalogue through
# it and `ruby dilla.rb bed` plays it under the narration. These pin what the
# operator asked of it and what is easiest to lose in an edit: every piece of
# the catalogue voiced, nothing played that the engine did not synthesise, no
# setting without a reader, and a rendered piece that lands where it should.
class TestDillaBed < Minitest::Test
  BED_SOURCE = File.read(File.expand_path("../dilla/dilla.rb", __dir__))[/^module Bed\n.*?^end\n/m]

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
      DESCRIPTIVE_KEYS.include?(key) || BED_SOURCE.match?(/BED\.fetch\("#{key}"\)|BED\.dig\("#{key}"|BED\["#{key}"\]/)
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
