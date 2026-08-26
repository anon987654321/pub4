# frozen_string_literal: true

# One tonal centre across the rotation.
#
# The eight Dilla-produced progressions resolve to two centres, and they are a
# tritone apart — the maximally distant relationship there is:
#
#   Bb   db_major_minor_fall, maj7_minor_cycle, eb_minor_two_chord, alternating_minor7_pair
#   E    pedal_e_descent, syncopated_slash_ninth, e_major_third_rise, major7_relative_minor_turn
#
# Each is coherent on its own and the pair is not, so a stream alternating
# between them has no tonal centre at all. Sampling producers do not work this
# way: a beat tape holds a key, or moves by fourths and relative minors, because
# that is what lets one track follow another. Dilla's own sequencing on Donuts
# moves between related centres, not across a tritone every other track.
#
# So progressions are transposed to a shared tonic. The chords keep their
# quality, their extensions, their voicing and their slash bass — only the root
# moves, which is transposition rather than reharmonisation. Nothing about a
# progression's internal logic changes.
module KeyLock
  PITCH_CLASS = {
    "C" => 0, "B#" => 0, "C#" => 1, "Db" => 1, "D" => 2, "D#" => 3, "Eb" => 3,
    "E" => 4, "Fb" => 4, "E#" => 5, "F" => 5, "F#" => 6, "Gb" => 6, "G" => 7,
    "G#" => 8, "Ab" => 8, "A" => 9, "A#" => 10, "Bb" => 10, "B" => 11, "Cb" => 11,
  }.freeze

  # Flat spelling throughout: the source data is already mostly Db/Eb/Bb, and
  # mixing Db with C# inside one rotation reads as two different keys on paper
  # even when it sounds like one.
  NAMES = %w[C Db D Eb E F Gb G Ab A Bb B].freeze

  # Root, then everything else (quality, extensions), then an optional slash bass.
  SYMBOL = /\A([A-G][#b]?)([^\/]*)(?:\/([A-G][#b]?))?\z/

  module_function

  def enabled? = ENV.fetch("KEY_LOCK", "1") != "0"

  # Default Bb: half the rotation already resolves there, so locking to it moves
  # four progressions instead of eight and keeps the ones most people know
  # (db_major_minor_fall, maj7_minor_cycle) at their original pitch.
  def target = ENV.fetch("KEY_LOCK_TONIC", "Bb")

  def pitch_class(name) = PITCH_CLASS[name.to_s]

  def transpose_symbol(symbol, semitones)
    return symbol if semitones.zero?

    m = SYMBOL.match(symbol.to_s)
    return symbol unless m

    root, quality, bass = m[1], m[2], m[3]
    pc = pitch_class(root)
    return symbol unless pc

    out = +"#{NAMES[(pc + semitones) % 12]}#{quality}"
    if bass && (bass_pc = pitch_class(bass))
      out << "/#{NAMES[(bass_pc + semitones) % 12]}"
    end
    out
  end

  # Where the progression comes to rest.
  #
  # Normally that is the last chord — these are loops, so the last chord is what
  # turns back to the first.
  #
  # But a pedal point overrides it, and pedal_e_descent is exactly that case:
  # D/E Db/E C/E Bm/E Bbm/E Am/E is a chromatic descent *over a standing E*.
  # Reading its last chord gives A and transposes the whole figure up a semitone,
  # which moves the pedal off E to F and lands the piece a semitone from where
  # the ear puts it. The pedal is the tonal centre; the upper voices are what
  # move against it. So when a clear majority of chords share one slash bass,
  # that bass is the tonic.
  PEDAL_SHARE = 0.6

  def tonic_of(chords)
    parsed = Array(chords).filter_map { |c| SYMBOL.match(chord_name(c)) }
    return nil if parsed.empty?

    basses = parsed.filter_map { |m| m[3] }
    if basses.size >= parsed.size * PEDAL_SHARE
      pedal, count = basses.tally.max_by { |_name, n| n }
      return pedal if pedal && count >= basses.size * PEDAL_SHARE
    end

    parsed.last[1]
  end

  def chord_name(chord) = chord.is_a?(Hash) ? (chord[:name] || chord["name"]) : chord

  # Shortest path, so a progression never moves more than six semitones. A
  # tritone is symmetric; +6 and -6 are the same pitch classes, and +6 is chosen
  # for stability rather than because the direction matters.
  def interval_to_target(tonic, target_name = target)
    from = pitch_class(tonic)
    to = pitch_class(target_name)
    return 0 unless from && to

    delta = (to - from) % 12
    delta > 6 ? delta - 12 : delta
  end

  # Transposes a progression so it resolves to the shared tonic.
  #
  # The :hz array moves with the name. The first version deleted it, on the
  # assumption that it would be re-derived downstream from the symbol — some
  # paths do that (harmony_engine's normalize_chord_pads), but the lead does not:
  # lead_scale_locked_tones_hz opens with `return [] unless chord[:hz]&.any?`
  # and derives the lead's entire note pool from those frequencies. An hz-less
  # chord therefore silently switched the lead's scale lock off, so the leads
  # stopped following the harmony they were playing over — audible as a lead in
  # a different key from the chords underneath it.
  #
  # Transposing the frequencies is also more honest than dropping them:
  # a semitone shift is a ratio, the array is already in Hz, and re-deriving from
  # a symbol loses any voicing the source data encoded.
  def transpose_hz(list, semitones)
    ratio = 2.0**(semitones / 12.0)
    Array(list).map { |hz| (hz.to_f * ratio).round(2) }
  end

  def lock(chords, target_name = target)
    return chords unless enabled?

    tonic = tonic_of(chords)
    return chords unless tonic

    semis = interval_to_target(tonic, target_name)
    return chords if semis.zero?

    Array(chords).map do |chord|
      if chord.is_a?(Hash)
        moved = chord.merge(name: transpose_symbol(chord_name(chord), semis))
        hz = chord[:hz] || chord["hz"]
        moved[:hz] = transpose_hz(hz, semis) if hz.respond_to?(:map) && !Array(hz).empty?
        moved
      else
        transpose_symbol(chord, semis)
      end
    end
  end
end
