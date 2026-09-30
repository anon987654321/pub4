# frozen_string_literal: true

# Pitch: improvised progressions and lines, keys and modes, the harmony engine,
# the composition engine, the harmony score and lead, and theory.

# Twelve progressions the engine writes itself.
#
# The catalogue it plays is otherwise seven progressions taken off records, each
# with a date and a source. This is the other half: the same music understood
# well enough to make more of it, rather than only to quote it.
#
# Five languages, and each is a small set of rules about where a root may move
# next and what quality sits on it. That is what a style is at this level --
# not a sound, which the synthesiser decides, and not a groove, which the pocket
# decides, but a constraint on harmonic motion. Bach's is the strictest and
# Flying Lotus's is the loosest, and the difference between them is legible in
# how many roots each one allows.
#
# Every chord is emitted with explicit frequencies rather than a name to be
# looked up. The lookup keeps the FIRST entry under a name, and these are merged
# last, so a generated "Am9" would silently resolve to somebody else's voicing.
# The `imp` tag on every name follows the convention the tension chords already
# set -- Ebm7fil, E7climax, Cm11nc -- and keeps the quality parseable.
module DillaImprovisation
  # A4 = 440, MIDI 69. Everything else follows.
  def self.hz(midi) = (440.0 * (2.0**((midi - 69) / 12.0))).round(2)

  PITCH_NAMES = %w[C Db D Eb E F Gb G Ab A Bb B].freeze

  # Intervals above the root, in semitones.
  QUALITIES = {
    "maj" => [0, 4, 7],
    "min" => [0, 3, 7],
    "dim" => [0, 3, 6],
    "maj7" => [0, 4, 7, 11],
    "maj9" => [0, 4, 7, 11, 14],
    "m7" => [0, 3, 7, 10],
    "m9" => [0, 3, 7, 10, 14],
    "m11" => [0, 3, 7, 10, 17],
    "7" => [0, 4, 7, 10],
    "sus2" => [0, 2, 7],
    "sus4" => [0, 5, 7],
    "sus9" => [0, 5, 7, 10, 14],
    "add9" => [0, 4, 7, 14],
    # A quartal stack is fourths rather than thirds, so it names no mode: it is
    # the reason a Flying Lotus chord can sit under any bass note at all.
    "q4" => [0, 5, 10, 15],
    "q4b" => [0, 5, 10, 15, 20],
    # The soul-jazz colours the live improviser walks between (data/live.yml):
    # the raised eleventh, the thirteenth, the altered dominant, the six-nine
    # and the suspended thirteenth.
    "maj7#11" => [0, 4, 7, 11, 18],
    "13" => [0, 4, 10, 14, 21],
    "7alt" => [0, 4, 10, 13, 15],
    "m6/9" => [0, 3, 7, 9, 14],
    "13sus" => [0, 5, 10, 14, 21],
  }.freeze

  # Where the chords sit. Low enough to be a bed, high enough that a four-note
  # stack does not turn to mud below the bass.
  ROOT_MIDI = 50 # D3

  class << self
    # --- the five languages ------------------------------------------------
    #
    # Each returns [[root_offset_in_semitones, quality], ...] against a tonic.

    # Bach: motion by descending fifths, which is the sequence itself, with the
    # dominant suspended before it resolves. The suspension is prepared -- the
    # note held into it belongs to the chord before -- and it falls by step, the
    # only two things that make a suspension a suspension rather than a wrong
    # note. Outer voices never move in parallel fifths or octaves; the voicing
    # operators downstream enforce that, and the root motion here never asks
    # them to.
    def bach_descending_fifths
      [[0, "min"], [5, "min"], [10, "maj"], [3, "maj7"], [8, "maj"], [1, "dim"], [7, "sus4"], [0, "min"]]
    end

    def bach_suspension_chain
      [[0, "min"], [7, "sus4"], [7, "maj"], [5, "min"], [0, "sus4"], [0, "min"], [10, "maj7"], [0, "min"]]
    end

    # Grieg: a pedal underneath, and above it the mixture -- the lowered seventh
    # borrowed against the raised one, and a chromatic mediant that belongs to
    # no key the piece has been in. The motif is the signature and it is two
    # intervals: a minor second down, then a major third down. Here it is the
    # root line of the last three chords, so the tune is in the harmony rather
    # than laid over it.
    def grieg_pedal_mixture
      [[0, "m9"], [10, "add9"], [8, "maj7"], [0, "m9"], [0, "m9"], [11, "maj"], [7, "min"], [0, "m9"]]
    end

    def grieg_motif_fall
      [[0, "min"], [10, "maj"], [5, "min"], [0, "min"], [0, "min"], [11, "min"], [7, "maj7"], [0, "m9"]]
    end

    # Dilla: one quality, planed. The chords do not resolve to each other, they
    # are the same shape moved -- which is why the language survives being cut
    # out of a record and looped, and why functional analysis says nothing
    # useful about it. Slash chords over a pedal are the other half: the bass
    # stays and the harmony walks over it.
    def dilla_planing_m9
      [[0, "m9"], [-2, "m9"], [-3, "m9"], [-5, "m9"], [0, "m9"], [-2, "m9"], [-4, "m9"], [-5, "m9"]]
    end

    def dilla_maj9_walk
      [[0, "maj9"], [-1, "maj9"], [-3, "maj9"], [-4, "maj9"], [0, "maj9"], [-1, "maj9"], [2, "maj9"], [0, "maj9"]]
    end

    def dilla_slash_pedal
      [[0, "m11"], [5, "m9"], [3, "maj9"], [10, "m9"], [0, "m11"], [5, "m9"], [8, "maj9"], [0, "m11"]]
    end

    def dilla_chromatic_drop
      [[0, "m9"], [-1, "m9"], [-2, "m9"], [-3, "m9"], [-4, "m9"], [-3, "m9"], [-1, "m9"], [0, "m9"]]
    end

    # Flying Lotus: quartal stacks, so nothing names a mode; roots a major third
    # apart, which is the chromatic mediant leap and belongs to two keys at once;
    # and no return home. The last chord is deliberately not the first -- the
    # language is a refusal to resolve, and ending on the tonic would undo it.
    def flylo_quartal_mediants
      [[0, "q4"], [4, "q4"], [8, "q4b"], [4, "q4"], [-4, "q4"], [-8, "q4b"], [3, "q4"], [8, "q4"]]
    end

    def flylo_unresolved_stack
      [[0, "q4b"], [6, "q4"], [1, "q4"], [8, "q4b"], [3, "q4"], [-2, "q4"], [7, "q4b"], [6, "q4"]]
    end

    # Röyksopp: the bass does not move. Everything above it is suspended -- the
    # second and the fourth standing in for the third, so no chord commits to
    # major or minor -- and the sixth is raised, which is Dorian and is the one
    # degree separating this from ordinary minor.
    def royksopp_static_sus
      [[0, "sus2"], [0, "sus4"], [0, "m9"], [0, "sus2"], [5, "sus2"], [0, "sus4"], [10, "sus2"], [0, "m9"]]
    end

    def royksopp_dorian_lift
      [[0, "m9"], [5, "maj"], [10, "sus2"], [0, "m9"], [2, "min"], [5, "maj"], [10, "add9"], [0, "m9"]]
    end

    # The twelve, in the order a demo plays them: each language's own pieces
    # together, so a listener hears a voice rather than a shuffle.
    def languages
      {
        bach_descending_fifths: bach_descending_fifths,
        bach_suspension_chain: bach_suspension_chain,
        grieg_pedal_mixture: grieg_pedal_mixture,
        grieg_motif_fall: grieg_motif_fall,
        dilla_planing_m9: dilla_planing_m9,
        dilla_maj9_walk: dilla_maj9_walk,
        dilla_slash_pedal: dilla_slash_pedal,
        dilla_chromatic_drop: dilla_chromatic_drop,
        flylo_quartal_mediants: flylo_quartal_mediants,
        flylo_unresolved_stack: flylo_unresolved_stack,
        royksopp_static_sus: royksopp_static_sus,
        royksopp_dorian_lift: royksopp_dorian_lift,
      }
    end

    # --- realisation -------------------------------------------------------

    # The tonic each language is improvised on.
    #
    # Drawn, not fixed, because "improvised" that comes back in the same key
    # every time is a recording. Drawn from a seed and recorded, because an
    # improvisation nobody can play again is lost -- which is the same rule the
    # render seed follows. IMPROV_SEED replays a set exactly.
    def seed
      @seed ||= (ENV["IMPROV_SEED"] || ENV["DEMO_SEED"] || Random.new_seed % 1_000_000_000).to_i
    end

    def tonic_for(name)
      # Seeded on the name as well as the run, so two languages in one demo do
      # not land in the same key by accident.
      rng = Random.new(seed + name.to_s.each_char.sum(&:ord))
      # Db3 to B3. A whole octave of tonics, and none low enough to make a
      # five-note stack unreadable.
      ROOT_MIDI + rng.rand(0..11)
    end

    def chord_name(root_midi, quality)
      "#{PITCH_NAMES[root_midi % 12]}#{quality}imp"
    end

    def chord_for(root_midi, quality)
      intervals = QUALITIES.fetch(quality)
      { name: chord_name(root_midi, quality),
        hz: intervals.map { |semitones| hz(root_midi + semitones) } }
    end

    # Every distinct chord the twelve use, for the pad lookup.
    def chords
      progression_chords.values.flatten(1).uniq { |chord| chord[:name] }
    end

    # name => [chord, ...], realised once per run.
    def progression_chords
      @progression_chords ||= languages.to_h do |name, spec|
        tonic = tonic_for(name)
        [name, spec.map { |offset, quality| chord_for(tonic + offset, quality) }]
      end
    end

    # name => [chord name, ...], which is the shape CHORD_PROGRESSIONS holds.
    def progressions
      progression_chords.transform_values { |chords| chords.map { |chord| chord[:name] } }
    end

    def names = languages.keys

    # --- the live walk ------------------------------------------------------
    #
    # The live improviser does not play a progression, it chooses one chord at
    # a time: from [degree, quality] to one of the places data/live.yml says
    # that chord tends to go. A Markov walk, so it never repeats a loop and it
    # never leaves the language.
    def walk(moves, state, rng) = moves.fetch(state).sample(random: rng)

    def pitch_classes(key, degree, quality) = QUALITIES.fetch(quality).map { |i| (key + degree + i) % 12 }

    # Each tone of the next chord goes to the note nearest the voice that sat
    # at its index in the last one, inside the range, so the chords move by
    # the smallest steps they can and the pad never jumps register.
    def nearest_voicing(pitch_classes, previous, range:, first:)
      target = previous.empty? ? first : previous
      pitch_classes.each_with_index.map do |pc, index|
        centre = target[index] || target.last
        range.select { |m| m % 12 == pc }.min_by { |m| (m - centre).abs }
      end.sort.uniq
    end

    # One line an operator can read back, and the seed that reproduces it.
    def report
      progression_chords.map do |name, chords|
        format("  %-24s %s", name, chords.map { |c| c[:name].sub(/imp\z/, "") }.join(" "))
      end
    end
  end
end

require_relative "sound"

# A lead and a bass, worked out from the chords rather than written down.
#
# The engine has always had parts that voice a chord -- harmony_lead stacks its
# tones, the pad stack sustains them. This is the other kind of part: a single
# line that moves against the harmony instead of filling it in, which is what a
# player adds and a voicing cannot.
#
# It lives here rather than in the live script because both want it. Live plays
# these notes at the speakers; a render plays the same notes through the master
# chain. One generator, so the take you keep is the take you heard.
module ImprovisedLine
  module_function

  def hz_to_midi(hz) = 69.0 + (12.0 * Math.log2(hz / 440.0))
  def midi_to_hz(midi) = 440.0 * (2.0**((midi - 69) / 12.0))

  # Which scale a chord implies, by the intervals actually in it.
  #
  # A minor seventh belongs to Dorian rather than to natural minor -- the raised
  # sixth is what keeps a line over it from turning mournful. A major seventh
  # takes Lydian, whose raised fourth is the only note that makes it sound
  # chosen rather than plain. A suspended chord has no third to commit to, so it
  # takes the pentatonic, which has no note that can be wrong.
  #
  # Semitones above the chord root. First match wins.
  SCALES = [
    [[4, 11], [0, 2, 4, 6, 7, 9, 11]],
    [[3, 10], [0, 2, 3, 5, 7, 9, 10]],
    [[4, 10], [0, 2, 4, 5, 7, 9, 10]],
    [[3, 7], [0, 2, 3, 5, 7, 8, 10]],
    [[4, 7], [0, 2, 4, 5, 7, 9, 11]],
  ].freeze

  PENTATONIC_MINOR = [0, 3, 5, 7, 10].freeze

  # The root is the lowest note the chord actually voices and the intervals are
  # measured from it -- both from the frequencies rather than from the chord's
  # name, because a name is a label somebody typed and the frequencies are what
  # will be heard.
  def scale_for(chord_hz)
    pitches = chord_hz.map { |hz| hz_to_midi(hz).round }.sort
    root = pitches.first
    intervals = pitches.map { |p| (p - root) % 12 }.uniq
    match = SCALES.find { |required, _| required.all? { |i| intervals.include?(i) } }
    [root, match ? match[1] : PENTATONIC_MINOR]
  end

  # The two notes that say which chord this is.
  #
  # Root and fifth are identical in a major, a minor and a dominant, so a line
  # built on them describes nothing. The third and the seventh are what differ,
  # and they are where a listener hears the change -- which is why they are
  # called the guide tones and why a line states them first.
  def guide_tones(chord_hz)
    root = hz_to_midi(chord_hz.min).round
    intervals = chord_hz.map { |hz| (hz_to_midi(hz).round - root) % 12 }.uniq
    guides = (intervals & [3, 4]) + (intervals & [10, 11])
    guides.empty? ? (intervals & [2, 5, 7]).first(1) : guides
  end

  # A line over one chord, into the next.
  #
  # Three notes, not eight. A lead that plays every subdivision is an exercise,
  # and against a pad it is also a fight: both parts end up sustaining and
  # neither is heard. What is left is the part that carries meaning --
  #
  #   TARGET   the downbeat is a guide tone, so the line states the chord at the
  #            moment the chord arrives.
  #   APPROACH a semitone from the next target, on the OFFBEAT before it. Chord
  #            tones on the beat and chromatics off it is the placement that
  #            makes a note from outside the key sound intended.
  #   LAND     the next chord's guide tone, so the line crosses the change
  #            rather than stopping at it.
  #
  # DENSITY adds notes back for anyone who wants them: at 1.0 a passing tone
  # returns between the target and the approach.
  # register 1, not 2. Two octaves above a chord already voiced around middle C
  # puts a line near the top of the piano, where nothing masks it and every
  # imperfection is exposed. One octave up sits it over the pad and still under
  # the ceiling.
  def lead(chord_hz, next_chord_hz, at, duration, rng, register: 1)
    root, scale = scale_for(chord_hz)
    base = root + (12 * register)
    guides = guide_tones(chord_hz)
    return [] if guides.empty?

    step = duration / 8.0
    return [] if step < 0.06

    density = (ENV["LEAD_DENSITY"] || "0.35").to_f.clamp(0.0, 1.0)
    target = guides.sample(random: rng)
    notes = []
    place = lambda do |semis, at_step, length, gain|
      notes << { hz: midi_to_hz(base + semis).round(2), at: (at + (at_step * step)).round(4),
                 held: (step * length).round(4), gain: gain }
    end

    place.call(target, 0, 2.2, 0.34)

    if rng.rand < density
      degree = (scale.index(target) || 0) + [-2, -1, 1, 2].sample(random: rng)
      octave, index = degree.clamp(-7, 13).divmod(scale.length)
      place.call((12 * octave) + scale[index], 3, 1.0, 0.26)
    end

    return notes unless next_chord_hz

    next_root, = scale_for(next_chord_hz)
    next_guides = guide_tones(next_chord_hz)
    return notes if next_guides.empty?

    landing = (next_root - root) + next_guides.sample(random: rng)
    landing -= 12 while landing - target > 7
    landing += 12 while target - landing > 7
    place.call(landing + (rng.rand < 0.5 ? -1 : 1), 6.5, 0.5, 0.24)
    place.call(landing, 7.0, 1.4, 0.32)
    notes
  end

  # The bass, which is two traditions and they decide different things.
  #
  # Bach's continuo bass is a voice: it lands on the root where the harmony
  # changes and walks by step through the notes between this root and the next,
  # so the line arrives somewhere instead of restating the chord it sits under.
  # That chooses the notes.
  #
  # The dub bass chooses when and how low. Family Man rests on the one and lands
  # after it, the octave answers in the gap, and the note is long enough to
  # still be sounding when the next arrives.
  def bass(chord_hz, next_root_hz, at, duration, rng)
    root = hz_to_midi(chord_hz.min).round
    root -= 12 while root > 40
    root += 12 while root < 28

    notes = [{ hz: midi_to_hz(root).round(2), at: (at + (duration * 0.12)).round(4),
               held: (duration * 0.55).round(4), gain: 0.85 }]

    if duration > 1.0 && rng.rand < 0.6
      notes << { hz: midi_to_hz(root + 12).round(2), at: (at + (duration * 0.5)).round(4),
                 held: (duration * 0.2).round(4), gain: 0.5 }
    end

    if next_root_hz && duration > 0.9
      target = hz_to_midi(next_root_hz).round
      target -= 12 while target > 40
      target += 12 while target < 28
      gap = target - root
      if gap != 0 && gap.abs <= 7
        step = gap.positive? ? [1, 2].sample(random: rng) : [-1, -2].sample(random: rng)
        notes << { hz: midi_to_hz(root + step).round(2), at: (at + (duration * 0.82)).round(4),
                   held: (duration * 0.16).round(4), gain: 0.6 }
      end
    end
    notes
  end

  # The Copy Machine, applied to notes rather than to a finished wav.
  #
  # CopyMachine.plan already decides everything -- which ratios, how far each
  # copy is delayed, how much quieter it is. This reads that same plan and
  # builds the copies as notes: a ratio becomes a transposition, a delay becomes
  # a later start, a gain becomes a quieter note. Reuse rather than a second
  # implementation, so the device sounds like itself whichever way it is
  # reached.
  #
  # Two of the plan's five decisions do not survive the translation and it is
  # worth saying which: a note has no direction, so `reverse` is dropped, and
  # AnalogSynth places its own stereo image, so `pan` is dropped. Ratio, delay
  # and gain are the three that carry.
  # Octaves only, and downward by preference.
  #
  # The harmonic family includes 3.0 and 0.333 -- an octave and a fifth away in
  # both directions. On a sustained sample that is a cloud; on a lead line
  # already sitting above the pad it is a piercing fifth over every note, which
  # is what an unusable lead sounds like. Copies here stay octaves, so a copy
  # can only ever double a note the line already played.
  LEAD_RATIOS = [1.0, 0.5, 2.0, 0.25].freeze

  def copies(notes, copies: 3, family: :harmonic, drift: 220.0, seed: 4242)
    return notes if notes.empty? || copies.to_i < 2

    plan = CopyMachine.plan(copies: copies, family: family, reverse: 0.0,
                            width: 0.0, drift: drift, seed: seed)
    plan.flat_map do |copy|
      next notes if copy.index.zero?

      ratio = LEAD_RATIOS[copy.index % LEAD_RATIOS.length]
      notes.map do |note|
        note.merge(hz: (note[:hz] * ratio).round(2),
                   at: (note[:at] + (copy.delay_ms / 1000.0)).round(4),
                   gain: (note[:gain] * copy.gain * 0.6).round(4))
      end
    end
  end
end

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

require "set"

# Which progressions belong in the same rotation.
#
# The stream ran eight progressions — Dilla's own — because widening it meant
# key chaos: the catalogue spans 248 progressions across every mode, and putting
# Lydian next to Phrygian next to whole-tone has no centre. KeyLock removes that
# objection by bringing everything to one tonic, so the question becomes the
# narrower and more useful one: which progressions share a *scale*, not just a
# root.
#
# The collection is Bb Dorian/Aeolian — the bittersweet soul region, ♭3 ♭6 ♭7
# with the Dorian ♮6 available — plus the major third, because the parallel
# major is not a foreign key. Alternating Bb minor and Bb major is modal
# interchange, which is idiomatic to this music rather than a mistake; `e_major_third_rise`
# (Bbmaj7 Dm7 Gm7 Bb7) is Dilla's own and it is parallel major.
FAMILY_DEGREES = %w[Bb C Db D Eb F Gb G Ab].freeze

module ModalFamily
  # 0.80, chosen by measurement rather than taste. At 1.00 and 0.90 the filter
  # drops two of Dilla's eight; at 0.85 it still drops one; at 0.75 it admits 239
  # of 248 and has stopped filtering. 0.80 keeps all eight and excludes 45.
  #
  # Roots rather than full chord tones: an extension can borrow from outside the
  # collection for one chord without leaving the key, which is the whole point of
  # a borrowed dominant or a tritone sub. Where the *root* leaves, the progression
  # has actually modulated.
  THRESHOLD = 0.80

  module_function

  def enabled? = ENV.fetch("MODAL_ROTATION", "1") != "0"

  def threshold = (ENV["MODAL_THRESHOLD"] || THRESHOLD).to_f

  def collection
    @collection ||= Set.new(FAMILY_DEGREES.filter_map { |n| KeyLock::PITCH_CLASS[n] })
  end

  def roots(chords)
    Array(chords).filter_map { |c| KeyLock::SYMBOL.match(KeyLock.chord_name(c))&.[](1) }
  end

  # Fit is measured *after* the key lock, since that is the form the rotation
  # actually plays. Measuring the source keys would reject anything not already
  # in Bb, which is most of the catalogue.
  def fit(chords)
    locked = KeyLock.lock(chords)
    pcs = roots(locked).filter_map { |r| KeyLock::PITCH_CLASS[r] }
    return 0.0 if pcs.empty?

    pcs.count { |p| collection.include?(p) }.to_f / pcs.size
  end

  def compatible?(chords) = fit(chords) >= threshold

  # Memoised per progression name: the pool is rebuilt per track and the fit is a
  # pure function of a frozen table.
  def compatible_name?(name, chords)
    @cache ||= {}
    key = name.to_s
    return @cache[key] if @cache.key?(key)

    @cache[key] = compatible?(chords)
  end

  # The rotation: the given core first, then everything else in the family.
  #
  # Widened outward from the core rather than replacing it —
  # DILLA_PROGRESSIONS_ONLY narrowing to Dilla's own was a deliberate choice
  # (2026-07-27), and this keeps those eight while admitting the rest of the
  # catalogue that belongs in the same key and mode. MODAL_ROTATION=0 restores
  # the narrow pool exactly.
  # `always` names progressions that skip the fit test entirely.
  #
  # The test is diatonic: it asks what share of a progression's roots fall in one
  # nine-note collection. That is the right question for 248 catalogue entries of
  # unknown provenance, and the wrong one for a deliberate two-centre vamp, which
  # fails it by construction rather than by accident. Jamal's Pavanne locks to
  # Am7-Bbm7 and scores 0.50; So What locks to Bbm7-Bm7 and scores 0.75, both
  # under the 0.80 threshold — and a modal vamp a semitone apart is exactly the
  # device those two records are famous for.
  #
  # KeyLock already guarantees one tonal centre, so nothing here is protecting
  # against key chaos. Hand-curated, sourced progressions are therefore exempt:
  # they were chosen, and a heuristic for unvetted material should not overrule
  # that.
  def widen(core, catalogue, always: [])
    return core unless enabled?

    exempt = Array(always).map(&:to_s)
    extra = catalogue.filter_map do |name, chords|
      next if core.map(&:to_s).include?(name.to_s)
      next unless chords.is_a?(Array) && chords.size >= 2
      next unless exempt.include?(name.to_s) || compatible_name?(name, chords)

      name.to_s
    end
    (core.map(&:to_s) + extra.sort).uniq
  end
end

# Soul / neo-soul / soul-jazz harmony — voicing, validation, beauty scoring,
# and progression transforms for Dilla-style chord beauty.
module DillaHarmony
  PAD_MIDI_MIN = 50.0
  # G5, not E5. At 76 a mid-register 13th sat three semitones above the ceiling,
  # so the whole chord was transposed down an octave to fit -- a 12-semitone lurch
  # in the middle of a progression, which is worse than a bright top voice. 50..79
  # is a Rhodes comp's range and PAD_LOWPASS still shapes the top.
  PAD_MIDI_MAX = 79.0
  # hz values are rounded to 2 dp, so a note's MIDI number lands a hair either
  # side of the integer: D4 measures 61.99998 and E5 measures 76.00003. Every
  # register comparison needs slack, or a boundary note is silently dropped.
  MIDI_TOL = 0.5
  MAX_PAD_VOICES = 5

  VOICING_STYLES = %i[spread quartal drop2 drop3 rootless so_what kenny_barron bill_evans cluster].freeze

  SOUL_PROFILES = %i[
    maj7_minor_cycle fourth_third_sixth_second_turn timeless_authentic minor_iv_loop
    major_lifting slash_ninth_cycle two_chord_hypnosis relative_major_turn minor_turnaround
    warm_minor_arc quartal_west_coast slow_ballad_wash minor_triad_walk neo_soul_pocket neo_soul
    dorian_iv_loop backdoor_resolve iv_borrow_minor electronium_loop electronium_classic
    bvi_bvii_minor ii_v_i_major ii_v_i_minor gospel_bIII flat_seven_lift warm_minor_vamp
    modern_quartal_stack funk_sixteenth_turn church_sus minMaj_color dominant_turn deceptive_turn
    plagal_jazz slash_neo_soul suspended_ballad minor_line_cliche stark_minor_pair piano_soul_turn
    jazz_ballad_waltz turnaround_ii_v modal_safe neo_iv_cycle
    modal_quartal_ladder minor_two_five_chain circle_fifths_descent walking_bass_descent
    lydian_glass_cycle pedal_upper_structures bossa_major9_turn phrygian_gold_arc
    two_chord_luminous mixo_sus_loop common_tone_drift third_cycle_triads
    drone_quartal_wash waltz_relative_lift half_time_gospel_plagal double_time_pocket
    whole_tone_bridge upper_triad_tower minor_add9_lullaby dominant_chain_home
  ].freeze

  BLOCKED_GENERATED = %i[polytonal negative_harmony neapolitan chromatic_mediant].freeze

  KEY_BORROW = {
    f_minor: %w[Dbmaj7 Ab Bbm7 Fm7 Fm9 Ebmaj7 Cm7],
    c_major: %w[Am9 Dm9 Fmaj9 G13 Ebmaj7 Bm7],
    d_minor: %w[Am7 Bbmaj7 Cmaj9 Fmaj9 Eb7 Gm7],
    eb_major: %w[Cm9 Fm7 Bb7 Abmaj9 Gm7],
    g_major: %w[Em9 Am9 Cmaj9 D13 Bm7],
    ab_major: %w[Fm7 Bbm7 Ebmaj7 Cm9 Dbmaj7],
  }.freeze

  SUBSTITUTIONS = {
    "m" => "m9", "maj" => "maj9", "7" => "13", "m7" => "m9", "maj7" => "maj9",
    "Fm" => "Fm9", "Ab" => "Abmaj9", "Db" => "Dbmaj7", "Dbmaj7" => "Dbmaj9",
    "Bbm" => "Bbm7", "Cm" => "Cm7", "Dm" => "Dm9", "Gm" => "Gm9", "Am" => "Am9",
    "Cmaj" => "Cmaj9", "Fmaj" => "Fmaj9", "Gmaj" => "Gmaj9", "Ebmaj7" => "Ebmaj9",
  }.freeze

  CONTRAST_VOICINGS = {
    quartal: :drop2, drop2: :rootless, rootless: :spread, cluster: :spread,
    spread: :quartal, drop3: :spread, so_what: :quartal, kenny_barron: :drop2,
    bill_evans: :rootless,
  }.freeze

  @last_progression_chords = nil

  module_function

  # djb2, not String#hash. Ruby randomises String#hash per process, so these
  # had seeded the same track name with a different number on every run and
  # the render was never the same twice — the same per-process reproducibility
  # fault sound.rb and the twenty-six dilla.rb sites corrected.
  def stable_hash(text)
    text.to_s.each_byte.reduce(5381) { |a, b| ((a * 33) + b) % 4_294_967_296 }
  end

  def remember_progression(chords)
    @last_progression_chords = chords
  end

  def last_progression_chords
    @last_progression_chords
  end

  def strip_voices(chord, count: 2)
    hz = chord[:hz].sort.last(count)
    chord.merge(hz:)
  end

  def chop_tones(chord)
    hz = chord[:hz].sort
    upper = hz.drop(1)
    chord.merge(hz: upper.empty? ? hz : upper)
  end

  def soul_profile?(track)
    sym = DillaLofiMachine.normalize_profile(track)
    SOUL_PROFILES.include?(sym) || DillaLofiMachine.harmony_profile?(sym)
  end

  def progression_insight(chords)
    return unless defined?(DillaMusicGems) && DillaMusicGems.coltrane?
    symbols = chords.map { |c| c[:name].to_s.sub(/_pedal\z/, "").sub(/_t\d+\z/, "") }
    DillaMusicGems.progression_analysis(symbols)
  end

  def hz_to_midi(hz)
    69.0 + 12.0 * Math.log2(hz / 440.0)
  end

  def midi_to_hz(midi)
    (440.0 * (2.0**((midi - 69.0) / 12.0))).round(2)
  end

  # Move the chord into the pad window AS A UNIT.
  #
  # This folded each note independently (`m += 12 while m < MIN; m -= 12 while
  # m > MAX`), which is the exact failure producer_dna's build_voicing documents
  # and guards against: a rootless spread puts the 9th above MIDI 76, folding it
  # down an octave lands it *under* the third, and a wide Rhodes voicing arrives
  # as a semitone cluster in the low-mid. Measured on the Players transcription
  # before this change: Ebmaj7 voiced D4 Eb4 G4 Bb4 -- the major 7th a semitone
  # below the root, the harshest interval available -- and the returning Cm9
  # voiced Eb3 G3 Bb3 C4, root above the 7th with the 9th gone.
  def clamp_register(midis)
    return midis if midis.empty?

    voiced = midis.sort
    shift = 0.0
    shift += 12.0 while voiced.first + shift < PAD_MIDI_MIN - MIDI_TOL
    while voiced.last + shift > PAD_MIDI_MAX + MIDI_TOL &&
          voiced.first + shift - 12.0 >= PAD_MIDI_MIN - MIDI_TOL
      shift -= 12.0
    end
    voiced = voiced.map { |m| m + shift }
    # Wider than the window even after transposing: thin from the top. A thinner
    # chord is still the same chord; one with its top voice folded under the bass
    # is a different one.
    # Half-semitone tolerance: hz values are rounded to 2 dp, so a note sitting
    # exactly on the ceiling (E5 = 659.25 Hz -> MIDI 76.00003) measured as above
    # it and was thrown away -- which is how G13 lost the thirteenth it is named
    # for while the four tones below it stayed.
    kept = voiced.select { |m| m <= PAD_MIDI_MAX + MIDI_TOL }
    kept.length >= 2 ? kept : voiced.first(2)
  end

  # Spacing that keeps a pad reading as a chord instead of a smear. A minor third
  # is the tightest interval that stays clear below the top octave, and a
  # sustained pad has no business holding a semitone anywhere.
  MUD_CEIL = 64.0

  def min_voice_gap(low)
    low < MUD_CEIL ? 3.0 : 2.0
  end

  # Octave-displace a crowded pair rather than dropping a voice. Every voicing this
  # runs on was built from known chord functions, so moving one an octave keeps all
  # of them present. Try both directions before giving up: raise the upper voice,
  # or if the ceiling is in the way, lower the other one. Raise-or-delete was the
  # only option here, and per-voice octave alignment in the voice-leading step
  # lands two voices a semitone apart often enough that it cost real tones -- Bb13
  # arrived as D4 G4, having lost the seventh with no room above to move it.
  def open_spacing(midis)
    voiced = midis.uniq.sort
    8.times do
      i = voiced.each_cons(2).find_index { |a, b| (b - a) < min_voice_gap(a) }
      break unless i

      up = voiced[i + 1] + 12.0
      down = voiced[i] - 12.0
      if up <= PAD_MIDI_MAX + MIDI_TOL
        voiced[i + 1] = up
      elsif down >= PAD_MIDI_MIN - MIDI_TOL
        voiced[i] = down
      else
        voiced.delete_at(i + 1)
      end
      voiced = voiced.uniq.sort
    end
    voiced
  end

  # Keep the comp in one register.
  #
  # Per-voice octave alignment minimises motion voice by voice, which lets a
  # voicing creep upward chord after chord until the ceiling forces it back down
  # in a single octave drop: measured as a 13-semitone lurch between Fm9 and Bb13
  # in the Players transcription, after the earlier fixes removed the clusters
  # that had been hiding it. Anchoring every chord to the first chord's centre
  # keeps the progression where a player's hands would stay.
  def anchor_register(midis, centre)
    return midis if midis.empty? || centre.nil?

    voiced = midis.sort
    (-2..2).map { |oct| voiced.map { |m| m + oct * 12.0 } }
           .select { |s| s.first >= PAD_MIDI_MIN - MIDI_TOL && s.last <= PAD_MIDI_MAX + MIDI_TOL }
           .min_by { |s| ((s.sum / s.length) - centre).abs } || clamp_register(voiced)
  end

  def register_centre(midis)
    midis.empty? ? nil : midis.sum / midis.length
  end

  def chord_intervals(hz)
    midis = hz.map { |h| hz_to_midi(h) }.sort
    root = midis.first
    midis.map { |m| ((m - root) % 12).round }.uniq
  end

  def apply_voicing(hz, style:, rootless: true)
    midis = hz.map { |h| hz_to_midi(h) }.sort
    root = midis.first
    ivs = chord_intervals(hz)
    # A chord with no third is suspended, quartal or a slash upper-structure by
    # construction -- the missing third is the point. The styles below rebuild a
    # voicing from assumed intervals and default a missing third to a MAJOR one,
    # which invents a note the chord does not contain: the E9sus4 written "D/E"
    # came back carrying a G# third and an F# ninth, neither of them in it. That
    # made the first chord of the default progression a different chord from the
    # other five (only the first goes through decorate_chord), which is the lurch
    # heard once per cycle. Leave such chords as written.
    return hz unless ivs.any? { |i| [3, 4].include?(i) }

    third_iv = ivs.find { |i| [3, 4].include?(i) } || 4
    fifth_iv = ivs.find { |i| [7, 6].include?(i) }
    seventh_iv = ivs.find { |i| [10, 11].include?(i) }
    ninth_iv = ivs.find { |i| [2, 14].include?(i) }
    eleventh_iv = ivs.find { |i| i == 5 }

    voiced = case style
             when :so_what, :quartal
               [root, root + 5, root + 10, root + 15].first(MAX_PAD_VOICES)
             when :rootless, :bill_evans, :kenny_barron
               # Subtractive, not generative.
               #
               # These built a shell from assumed intervals -- 3rd, 7th, 9th, 11th,
               # defaulting each one that was missing (`ninth_iv || 14`). On a 13
               # chord that discarded the thirteenth and invented a ninth the chord
               # never had: Bb13 came out Bb D F Ab with a 9th on top, which
               # chord_tones_preserved? then correctly rejected, so the curated
               # pipeline threw the voicing away and reverted to a root-position
               # stack. Half the Players transcription reached the render that way.
               #
               # Rootless means "the bass has the root", so take the root out of
               # what the chord actually contains and leave every other tone alone.
               # A triad has nothing to spare, so it keeps its root.
               shell = midis.length >= 4 ? midis.drop(1) : midis
               # The fifth goes only if there is an extension to keep the chord
               # recognisable without it. Dropping root and fifth from a plain 7th
               # leaves two pitch classes, which chord_tones_preserved? rejects --
               # so Fmaj7 lost its voicing and reverted to a root-position stack.
               if fifth_iv && shell.map { |m| ((m - root) % 12).round }.uniq.length >= 4
                 shell = shell.reject { |m| ((m - root) % 12).round == 7 }
               end
               shell
             when :drop2
               return hz if midis.length < 4
               ordered = midis.dup
               ordered[-2] -= 12.0 if ordered[-2] > PAD_MIDI_MIN
               ordered
             when :drop3
               return hz if midis.length < 4
               ordered = midis.dup
               ordered[-3] -= 12.0 if ordered[-3] > PAD_MIDI_MIN
               ordered
             when :spread
               # Only tones the chord has. The ninth was added whenever the chord
               # had three or more intervals (`if ninth_iv || ivs.length >= 3`,
               # defaulting to 14), so 13ths, 6ths and altered dominants all
               # sprouted a ninth and then failed the chord-tone check.
               spread = [root, root + (fifth_iv || 7)]
               spread << root + third_iv + 12
               spread << root + seventh_iv + 12 if seventh_iv
               spread << root + (ninth_iv == 2 ? 14 : ninth_iv) + 12 if ninth_iv
               spread += ivs.reject { |i| [0, third_iv, fifth_iv, seventh_iv, ninth_iv].include?(i) }
                             .map { |i| root + i + 12 }
               spread.uniq.first(MAX_PAD_VOICES)
             when :cluster
               [root, root + 1, root + 2, root + 6].first(MAX_PAD_VOICES)
             else
               midis
             end

    voiced = voiced.map(&:to_f)
    if rootless && style != :cluster && %i[spread quartal drop2 drop3].include?(style)
      voiced = voiced.reject { |m| (m - root).abs < 0.5 || ((m - root) % 12).abs < 0.5 && m <= root + 1 }
      voiced = [root + third_iv, root + (seventh_iv || 10) + 12, root + (ninth_iv || 14) + 12] if voiced.length < 3
    end

    clamp_register(open_spacing(voiced)).map { |m| midi_to_hz(m) }.first(MAX_PAD_VOICES)
  end

  def decorate_chord(chord, voicing: :spread, rootless: true)
    hz = apply_voicing(chord[:hz], style: voicing, rootless:)
    { name: chord[:name], hz:, bass_hz: chord[:bass_hz] || chord[:hz].min }
  end

  # The voicing a progression asked for.
  #
  # dilla_reference.yml declares `voicing: rootless` on all four documented
  # transcriptions and HARMONY_PROFILES carries it through, but the curated
  # pipeline hardcoded `rootless: false` and the stream's VOICING rotation was
  # only ever tested for `== :cluster` -- so every Dilla chord played its own root
  # while dilla_chord_bass_hz played it too, and the rotation was inaudible.
  def declared_voicing(cfg)
    raw = DillaLofiMachine.profile_entry(cfg[:track])&.dig(:voicing) || cfg[:voicing]
    style = raw.to_s.downcase.tr("-", "_").to_sym
    VOICING_STYLES.include?(style) ? style : :rootless
  end

  KEY_ALIASES = {
    /f minor/i => :f_minor, /c minor/i => :f_minor, /c# minor/i => :f_minor,
    /d minor/i => :d_minor, /bb/i => :d_minor, /dm/i => :d_minor,
    /c major/i => :c_major, /g major/i => :g_major, /e major/i => :g_major,
    /eb/i => :eb_major, /ab/i => :ab_major
  }.freeze

  def key_sym_for(cfg)
    key = DillaLofiMachine.profile_entry(cfg[:track])&.dig(:key).to_s
    KEY_ALIASES.each { |rx, sym| return sym if key.match?(rx) }
    :f_minor
  end

  def substitute_symbol(sym)
    SUBSTITUTIONS.fetch(sym.to_s, sym.to_s)
  end

  def apply_key_borrow(pads, cfg)
    return pads unless soul_profile?(cfg[:track])
    pool = KEY_BORROW[key_sym_for(cfg)]
    return pads unless pool&.any?
    rng = Random.new(stable_hash(cfg[:track]) + pads.length)
    pads.map.with_index do |ch, i|
      next ch unless (i % 8) == 6 && rng.rand < 0.45
      borrowed = pool[rng.rand(pool.length)]
      DillaLofiMachine.chord_from_symbol(borrowed).merge(name: borrowed)
    rescue StandardError
      ch
    end
  end

  def apply_recap_substitutions(pads, cfg, phases)
    return pads unless soul_profile?(cfg[:track])
    pads.map.with_index do |ch, i|
      phase = phases[i]
      next ch unless phase == :recapitulation
      sym = ch[:name].to_s
      sub = substitute_symbol(sym)
      next ch if sub == sym
      DillaLofiMachine.chord_from_symbol(sub).merge(name: sub, bass_hz: ch[:bass_hz])
    rescue StandardError
      ch
    end
  end

  def insert_secondary_dominants(pads, cfg)
    return pads if pads.length < 4 || !soul_profile?(cfg[:track])
    rng = Random.new(stable_hash(cfg[:track]) + 99)
    out = pads.dup
    [6, 7].each do |idx|
      next if idx >= out.length
      next unless rng.rand < 0.35
      root = hz_to_midi(out[idx][:hz].min)
      dom = { name: "V7/ii", hz: apply_voicing([midi_to_hz(root + 2)], style: :spread) }
      dom[:hz] = apply_voicing([midi_to_hz(root + 2)], style: :spread)
      out[idx] = dom
    rescue StandardError
      next
    end
    out
  end

  def insert_backdoor(pads, cfg)
    return pads unless soul_profile?(cfg[:track]) && ENV["BACKDOOR"] != "0"
    return pads if pads.length < 8
    idx = 7
    root = hz_to_midi(pads[idx][:hz].min)
    bk = { name: "bVII7", hz: apply_voicing([midi_to_hz(root - 2)], style: :rootless) }
    pads = pads.dup
    pads[idx] = bk
    pads
  end

  def reharm_every_fourth_loop(pads, cfg)
    return pads unless soul_profile?(cfg[:track]) && ENV["REHARM_LOOP"] == "1"
    return pads if pads.length < 4
    rng = Random.new(stable_hash(cfg[:track]))
    pads.map.with_index do |ch, i|
      next ch unless (i % 4) == 3 && rng.rand < 0.4
      sym = ch[:name].to_s
      tritone = sym.sub(/7\z/, "7alt").sub(/maj7/, "7#11")
      DillaLofiMachine.chord_from_symbol(tritone)
    rescue StandardError
      ch
    end
  end

  def pad_overlap_mul(prev, curr)
    return 1.0 unless prev && curr
    motion = root_motion_semitones(prev, curr)
    motion <= 2 ? 1.12 : 1.0
  end

  def enrich_progression(pads, cfg, phases: [], curated: false)
    return [pads, phases] if pads.empty?
    soul = soul_profile?(cfg[:track])
    skip_passing = curated || (soul && ENV["SOUL_ENRICH"] != "1")
    use_rootless = !curated && soul

    rng = Random.new((stable_hash(cfg[:track]) % 100_000) + pads.length)
    voicing = cfg[:voicing] || :spread
    recap_voicing = CONTRAST_VOICINGS.fetch(voicing, :drop2)
    out = []
    phases_out = []
    pads.each_with_index do |chord, i|
      phase = phases[i]
      chord_voicing = case phase
                      when :recapitulation then recap_voicing
                      when :development
                        if curated
                          voicing == :spread ? :drop2 : voicing
                        else
                          voicing == :spread ? :rootless : voicing
                        end
                      when :breakdown then curated ? voicing : :rootless
                      else voicing
                      end
      sym = chord[:name].to_s
      sym = substitute_symbol(sym) if soul && !curated && phase == :recapitulation && rng.rand < 0.5
      ch = sym != chord[:name].to_s ? (DillaLofiMachine.chord_from_symbol(sym) rescue chord) : chord
      # chord_voicing is computed a dozen lines above — drop2 through the
      # development, a contrast voicing at the recapitulation, rootless in
      # breakdowns — and the curated branch then discarded it and kept the
      # written register. Since every one of the 248 catalogue progressions is
      # curated, one voicing shape played through every section of every piece,
      # and nine voicing styles were never heard.
      #
      # The bypass exists to protect artist-verified voicings, which is a real
      # concern, so it stays reachable: CURATED_PHASE_VOICING=0 restores it. But
      # the default now varies, because a progression that voices identically in
      # its breakdown and its recapitulation is not being arranged at all.
      out << if curated && ENV["CURATED_PHASE_VOICING"] == "0"
               preserve_chord_register(ch)
             elsif curated
               # Rootless is for non-curated material, where the engine owns the
               # bass. Curated chords keep their root.
               decorate_chord(ch, voicing: chord_voicing, rootless: false)
             else
               decorate_chord(ch, voicing: chord_voicing, rootless: use_rootless)
             end
      phases_out << phase
      next if skip_passing
      next_chord = pads[(i + 1) % pads.length]
      motion = root_motion_semitones(chord, next_chord)
      passing_rate = curated ? 0.06 : 0.04
      if phase == :development && i < pads.length - 1 && motion <= 4 && rng.rand < passing_rate
        out << passing_cluster(chord, next_chord)
        phases_out << :development
      end
    end
    enriched = out.map.with_index do |c, i|
      phase = phases_out[i]
      shift = phase == :development && (i % 8) == 7 ? 1 : 0
      next c if shift.zero? || c[:name].to_s.start_with?("pass_")
      { name: "#{c[:name]}_t#{shift}", hz: c[:hz].map { |h| (h * (2**(shift / 12.0))).round(2) } }
    end
    [enriched, phases_out.first(enriched.length)]
  end

  def root_motion_semitones(a, b)
    a_root = hz_to_midi(a[:hz].min)
    b_root = hz_to_midi(b[:hz].min)
    diff = (b_root - a_root) % 12
    [diff, 12 - diff].min
  end

  def passing_cluster(a, b)
    a_root = hz_to_midi(a[:hz].min)
    b_root = hz_to_midi(b[:hz].min)
    mid = ((a_root + b_root) / 2.0).round
    cluster = [mid - 1, mid, mid + 1, mid + 4].map { |m| midi_to_hz(m + 12) }
    { name: "pass_#{mid}", hz: cluster.uniq.first(3) }
  end

  def preserve_chord_register(chord)
    hz = clamp_register(chord[:hz].map { |h| hz_to_midi(h) }).map { |m| midi_to_hz(m) }.uniq
    chord.merge(hz: hz.first(MAX_PAD_VOICES))
  end

  def chord_pitch_classes(chord)
    root_pc = hz_to_midi(chord[:hz].min).round % 12
    chord[:hz].map { |h| ((hz_to_midi(h).round - root_pc) % 12) }.uniq.sort
  end

  def chord_tones_preserved?(chord)
    sym = chord[:name].to_s.sub(/_pedal\z/, "").sub(/_t\d+\z/, "")
    ref = DillaLofiMachine.chord_from_symbol(sym)
    ref_pcs = ref[:hz].map { |h| hz_to_midi(h).round % 12 }.uniq.sort
    voiced_pcs = chord[:hz].map { |h| hz_to_midi(h).round % 12 }.uniq.sort
    return true if ref_pcs.empty?
    return false unless (voiced_pcs - ref_pcs).empty?
    (voiced_pcs & ref_pcs).length >= [ref_pcs.length - 1, 3].min
  rescue StandardError
    true
  end

  # SATB-style voice leading — bottom voice stays bottom, chord identity intact.
  def voice_lead_chords_indexed(chords, rootless: false, voicing: :rootless)
    return chords if chords.length <= 1

    # Shape every chord, not just the first. `targets.drop(1)` was the old
    # rootless: it removed the bottom voice of a root-position template stack,
    # which drops the root but leaves the rest of the stack closed and in the
    # order the template happened to list it. apply_voicing builds the shell the
    # style actually names (3rd, 7th, 9th for rootless) from the chord's own
    # intervals, and leaves sus/quartal/slash chords alone.
    shaped = chords.map { |c| decorate_chord(c, voicing:, rootless:) }
    led = [preserve_chord_register(shaped.first)]
    prev = led.first[:hz].map { |h| hz_to_midi(h) }.sort
    centre = register_centre(prev)
    shaped.drop(1).each do |nxt|
      targets = nxt[:hz].map { |h| hz_to_midi(h) }.sort
      # Not `[prev.length, ...].min`: that clamped every chord to the narrowest
      # voicing seen so far, and since targets are sorted ascending it always cut
      # from the top. One rootless 3-voice chord early in a progression therefore
      # deleted the thirteenth from every 13 chord after it -- Bb13 arrived as
      # D F Ab. `prev[vi] || prev.last` below already handles a shorter anchor.
      n_voices = [targets.length, MAX_PAD_VOICES].min
      voiced = n_voices.times.map do |vi|
        target = targets[vi] || targets.last
        anchor = prev[vi] || prev.last
        target + (((anchor - target) / 12.0).round * 12.0)
      end
      voiced = anchor_register(clamp_register(open_spacing(voiced)), centre)
      prev = voiced
      hz = dedupe_by_pitch(voiced).first(MAX_PAD_VOICES).map { |m| midi_to_hz(m) }
      led << { name: nxt[:name], hz:, bass_hz: nxt[:bass_hz] || nxt[:hz].min }
    end
    led
  end

  # Only the first chord was decorated here, so a progression opened with a
  # rootless spread and then played seven root-position template stacks nudged
  # into register -- audibly one good chord followed by a block-chord comp.
  def voice_lead_chords(chords, rootless: false, voicing: :spread)
    return chords if chords.length <= 1

    shaped = chords.map { |c| decorate_chord(c, voicing:, rootless:) }
    led = [shaped.first]
    prev = led.first[:hz].map { |h| hz_to_midi(h) }.sort
    centre = register_centre(prev)
    shaped.drop(1).each do |nxt|
      targets = nxt[:hz].map { |h| hz_to_midi(h) }.sort
      anchors = prev.dup
      voiced = targets.map do |target|
        anchor = anchors.empty? ? target : anchors.min_by { |a| pitch_class_dist(a, target) }
        anchors.delete(anchor) if anchors.length > 1
        target + ((anchor - target) / 12.0).round * 12.0
      end
      voiced = anchor_register(clamp_register(open_spacing(voiced)), centre)
      prev = voiced
      hz = dedupe_by_pitch(voiced).first(MAX_PAD_VOICES).map { |m| midi_to_hz(m) }
      led << { name: nxt[:name], hz:, bass_hz: nxt[:bass_hz] || nxt[:hz].min }
    end
    led
  end

  # Two voices on the same note are a doubled unison, not a chord tone, and the
  # engine was shipping them: of 165 voicings logged to progressions_log.txt, 33
  # carried a duplicated pitch, 27 had fewer than three distinct ones, and 9 were
  # a single pitch class repeated -- G/Bb came out D3 D3 D5, which is the fifth
  # three times with the root and third gone.
  #
  # The dedupe was there and could not catch them. It ran on the *frequencies*,
  # after midi_to_hz, so two voices at 146.83 Hz and 147.06 Hz are distinct
  # floats, survive uniq, and are both D3. They only became equal after
  # nearest_note rounded them for the log, which is why the log showed the
  # problem and the code could not see it.
  #
  # The near-collisions come from the octave-shift arithmetic above:
  # `target + ((anchor - target) / 12.0).round * 12.0`, then open_spacing,
  # clamp_register and anchor_register, each nudging a float. Rounding to the
  # semitone is the level the question is actually asked at -- a chord is a set
  # of pitches, not a set of frequencies.
  def dedupe_by_pitch(midis)
    midis.uniq(&:round)
  end

  def pitch_class_dist(a, b)
    diff = (a - b) % 12.0
    [diff, 12.0 - diff].min
  end

  def bass_voice_lead(chords)
    return chords if chords.length < 2
    prev_bass = hz_to_midi(chords.first[:bass_hz] || chords.first[:hz].min)
    chords.map.with_index do |ch, i|
      next ch if i.zero?
      target = hz_to_midi(ch[:bass_hz] || ch[:hz].min)
      step = target - prev_bass
      step = step - 12 if step > 7
      step = step + 12 if step < -7
      step = -step.clamp(-5, 5) if ENV["BASS_CONTRARY"] == "1" && step.abs > 4
      bass_midi = prev_bass + step
      bass_midi += 12.0 while bass_midi < 36.0
      bass_midi -= 12.0 while bass_midi > 60.0
      prev_bass = bass_midi
      ch.merge(bass_hz: midi_to_hz(bass_midi))
    end
  end

  # A ii-V that is actually a ii and a V, and actually chords.
  #
  # Three things were wrong. Each was built by handing apply_voicing a
  # single-element array, and one frequency has no third, so the guard at the top
  # of apply_voicing returned it untouched: every soul profile's turnaround was
  # two bare notes. The intervals were also swapped against their names -- `-5`
  # is a fourth below, the same pitch class as the fifth above, so "turn_ii" was
  # the dominant and "turn_V" the supertonic, and the pair resolved V-ii instead
  # of ii-V. And the tonic was read as `pads.last[:hz].min`, which stopped being
  # the root the moment the voicings went rootless: the lowest voice of a rootless
  # shell is its third or seventh, so the turnaround was transposed to whatever
  # that happened to be.
  #
  # The name is the reliable source for the root, so ask the chord table what the
  # last chord's root is, and build the two shells from real intervals.
  TURNAROUND_SHELLS = { turn_ii: [0, 3, 7, 10, 14], turn_V: [0, 4, 7, 10, 21] }.freeze

  # The upper structure's root, not the bass. A slash chord's reference voicing
  # starts on its bass note by construction, so Cm9/Bb would read as Bb -- a
  # whole tone off, and the turnaround built a whole tone off with it.
  def chord_root_midi(chord)
    sym = chord[:name].to_s.sub(/_pedal\z/, "").sub(/_t\d+\z/, "").split("/").first.to_s.strip
    hz_to_midi(DillaLofiMachine.chord_from_symbol(sym)[:hz].min)
  rescue StandardError
    hz_to_midi(chord[:hz].min)
  end

  def turnaround_chord(name, root_midi, voicing:, rootless:)
    hz = TURNAROUND_SHELLS.fetch(name).map { |iv| midi_to_hz(root_midi + iv) }
    decorate_chord({ name: name.to_s, hz: }, voicing:, rootless:)
  end

  def add_turnaround_tags(pads, cfg)
    return pads if pads.empty?
    return pads unless soul_profile?(cfg[:track])
    return pads if pads.length < 4

    tonic = chord_root_midi(pads.last)
    style = declared_voicing(cfg)
    rootless = style != :cluster
    pads + [turnaround_chord(:turn_ii, tonic + 2, voicing: style, rootless:),
            turnaround_chord(:turn_V, tonic + 7, voicing: style, rootless:)]
  end

  def validate_and_fix(chords)
    return chords if chords.length < 2
    fixed = [chords.first]
    chords.drop(1).each do |ch|
      prev = fixed.last
      clash = mid_register_clash?(prev, ch)
      if clash
        ch = decorate_chord(ch, voicing: :rootless)
        ch = { name: ch[:name], hz: ch[:hz].map { |h| hz_to_midi(h) }.sort.map { |m| midi_to_hz(m + 12) } } if clash
      end
      fixed << ch
    end
    fixed
  end

  def mid_register_clash?(a, b)
    a_midis = a[:hz].map { |h| hz_to_midi(h) }
    b_midis = b[:hz].map { |h| hz_to_midi(h) }
    a_midis.any? do |am|
      b_midis.any? do |bm|
        next false unless am.between?(55, 72) && bm.between?(55, 72)
        (am - bm).abs < 1.2 && pitch_class_dist(am, bm) > 2
      end
    end
  end

  def pedal_probability(cfg)
    return 0.0 if soul_profile?(cfg[:track])
    return 0.0 if DillaLofiMachine::CURATED_PROGRESSIONS.include?(cfg[:progression].to_sym)
    return 0.0 if %i[syncopated_slash_ninth syncopated_slash_alt].include?(cfg[:progression].to_sym)
    0.12
  end

  def chop_density(cfg, section)
    return 0.0 if section == :breakdown
    return 0.15 if soul_profile?(cfg[:track])
    return 0.25 if section == :intro
    0.45
  end

  def pad_sustain_mul(cfg, section, base_rng)
    mul = soul_profile?(cfg[:track]) ? base_rng.rand(0.94..1.08) : base_rng.rand(0.76..1.04)
    mul *= 0.7 if section == :breakdown
    mul *= 1.08 if section == :build && base_rng.rand < 0.5
    mul *= 1.04 if soul_profile?(cfg[:track]) && section == :main
    mul
  end

  def pad_entry_late(cfg, feel, step_p)
    return step_p * 2 + 0.012 if feel == :syncopated_slash_ninth
    return -step_p * 2 if feel == :chromatic_planing
    soul_profile?(cfg[:track]) ? step_p * 0.22 : 0.0
  end

  def score_beauty(chords)
    return 50 if chords.nil? || chords.empty?
    scores = []
    qualities = chords.map { |c| quality_score(c[:name].to_s) }
    scores << (qualities.sum / qualities.length)
    scores << register_score(chords)
    scores << motion_score(chords)
    scores << extension_score(chords)
    scores << clash_penalty(chords)
    raw = scores.sum / scores.length
    raw.clamp(0, 100).round(1)
  end

  def quality_score(name)
    return 85 if name =~ /maj9|m9|maj7|m7|m11|maj6|6|13|sus/i
    return 55 if name =~ /maj|min|m[^a-z]/i
    return 30 if name =~ /pass_|neg_|poly|dim|aug/i
    60
  end

  def register_score(chords)
    ok = chords.count do |c|
      c[:hz].all? { |h| hz_to_midi(h).between?(PAD_MIDI_MIN, PAD_MIDI_MAX) }
    end
    (ok.to_f / chords.length * 100).round
  end

  def motion_score(chords)
    return 80 if chords.length < 2
    motions = chords.each_cons(2).map { |a, b| root_motion_semitones(a, b) }
    smooth = motions.count { |m| m <= 5 }
    (smooth.to_f / motions.length * 100).round
  end

  def extension_score(chords)
    ext = chords.count { |c| c[:hz].length >= 3 }
    (ext.to_f / chords.length * 100).round
  end

  def clash_penalty(chords)
    clashes = chords.each_cons(2).count { |a, b| mid_register_clash?(a, b) }
    [100 - clashes * 15, 0].max
  end

  def normalize_chord_pads(pads)
    pads.map do |c|
      next c if c[:hz]&.any?
      DillaLofiMachine.chord_from_symbol(c[:name])
    rescue StandardError
      c
    end
  end

  # Researched soul loops — voicing + voice-leading only; no random reharm/borrow.
  def beautify_curated_pipeline(pads, cfg, phases: [])
    pads = normalize_chord_pads(pads)
    pads, phases = enrich_progression(pads, cfg, phases:, curated: true)
    style = declared_voicing(cfg)
    pads = voice_lead_chords_indexed(pads, rootless: style != :cluster, voicing: style)
    pads = pads.map do |ch|
      next ch if chord_tones_preserved?(ch)
      sym = ch[:name].to_s.sub(/_pedal\z/, "").sub(/_t\d+\z/, "")
      preserve_chord_register(DillaLofiMachine.chord_from_symbol(sym).merge(name: ch[:name], bass_hz: ch[:bass_hz]))
    rescue StandardError
      ch
    end
    # Bach/Dilla theory runtime (coltrane/head_music when available).
    if defined?(DillaTheoryRuntime)
      pads = DillaTheoryRuntime.refine_progression!(pads, cfg:)
    end
    report_harmony_beauty!(pads, cfg)
    [pads, phases]
  end

  # Theory-grounded scoring (DillaHarmonyScore: voice-leading distance,
  # common-tone retention, contrary motion, root-motion strength -- see that
  # file's header) after theory refinement has already run, so the report
  # reflects what actually got rendered, not the pre-refinement draft.
  # Informational only for now (BEAUTY_REPORT=1 to see it) -- not a gate,
  # since a false-reject here would silently swap out a fine progression for
  # no reason anyone could audit after the fact.
  def report_harmony_beauty!(pads, cfg)
    return unless defined?(DillaHarmonyScore) && ENV["BEAUTY_REPORT"] != "0"

    analysis = DillaHarmonyScore.analyze(pads)
    warn "harmony-beauty: #{cfg[:track]} score=#{analysis[:score]} #{analysis[:breakdown]}"
  rescue StandardError => e
    warn "harmony-beauty: scoring failed (#{e.class}: #{e.message})"
  end

  def beautify_pipeline(pads, cfg, phases: [])
    pads = normalize_chord_pads(pads)
    pads = apply_key_borrow(pads, cfg)
    pads = reharm_every_fourth_loop(pads, cfg)
    pads = insert_backdoor(pads, cfg)
    pads = validate_and_fix(pads)
    pads, phases = enrich_progression(pads, cfg, phases:)
    pads = apply_recap_substitutions(pads, cfg, phases)
    pads = insert_secondary_dominants(pads, cfg)
    pads = voice_lead_chords(pads, rootless: soul_profile?(cfg[:track]), voicing: declared_voicing(cfg))
    pads = bass_voice_lead(pads)
    pads = validate_and_fix(pads)
    pads = add_turnaround_tags(pads, cfg)
    if defined?(DillaTheoryRuntime)
      pads = DillaTheoryRuntime.refine_progression!(pads, cfg:)
    end
    report_harmony_beauty!(pads, cfg)
    [pads, phases]
  end

  def fix_chord_for_schedule(chord, prev_chord, curated: false)
    return chord unless prev_chord
    return preserve_chord_register(chord) if curated
    return decorate_chord(chord, voicing: :rootless) if mid_register_clash?(prev_chord, chord)
    chord
  end

  def block_generated?(track, style)
    soul_profile?(track) && BLOCKED_GENERATED.include?(style.to_sym)
  end

  def recommendations(scores)
    recs = []
    recs << "Use maj9/m9/m7 voicings — avoid bare triads and altered clusters." if scores[:extension] < 70
    recs << "Keep pad voices between MIDI 50–76." if scores[:register] < 75
    recs << "Smoother root motion — prefer steps and fourths." if scores[:motion] < 65
    recs << "Mid-register clash between adjacent chords — enable rootless voicings." if scores[:clash] < 80
    recs << "Harmony is soulful — evolve performer/groove next." if recs.empty?
    recs
  end

  def score_breakdown(chords)
    {
      overall: score_beauty(chords),
      extension: extension_score(chords),
      register: register_score(chords),
      motion: motion_score(chords),
      clash: clash_penalty(chords),
    }
  end
end

require_relative "ledger"
require "json"
require "fileutils"
require_relative "groove"

# Composition spine for dilla.rb — memory, arrangement, performers, tension,
# critique, scoring, evolution, and session persistence.
module DillaComposition
  PROJECT_DIR = ENV.fetch("DILLA_PROJECT_DIR", File.join(File.expand_path("..", __dir__), "project"))
  SESSION_PATH = File.join(PROJECT_DIR, "session.json")
  MOTIFS_PATH = File.join(PROJECT_DIR, "motifs.json")

  ARRANGEMENT_FORM = %i[intro verse hook verse bridge solo breakdown hook outro].freeze

  ARRANGEMENT_PROFILES = {
    intro:     { drums: 0.42, harmony: 0.62, lead: 0.08, bass: 0.55, swing_delta: -4, stereo: 0.35, saturation: 0.12, melodic_density: 0.2, fill_rate: 0.1 },
    verse:     { drums: 0.72, harmony: 0.92, lead: 0.32, bass: 0.78, swing_delta: 0, stereo: 0.55, saturation: 0.22, melodic_density: 0.45, fill_rate: 0.25 },
    hook:      { drums: 0.92, harmony: 1.0, lead: 0.82, bass: 0.88, swing_delta: 3, stereo: 0.78, saturation: 0.35, melodic_density: 0.75, fill_rate: 0.55 },
    bridge:    { drums: 0.58, harmony: 0.78, lead: 0.48, bass: 0.65, swing_delta: -2, stereo: 0.62, saturation: 0.28, melodic_density: 0.55, fill_rate: 0.35 },
    solo:      { drums: 0.68, harmony: 0.72, lead: 0.95, bass: 0.62, swing_delta: 5, stereo: 0.85, saturation: 0.4, melodic_density: 0.9, fill_rate: 0.45 },
    breakdown: { drums: 0.28, harmony: 0.55, lead: 0.12, bass: 0.42, swing_delta: -6, stereo: 0.4, saturation: 0.1, melodic_density: 0.15, fill_rate: 0.05 },
    outro:     { drums: 0.38, harmony: 0.48, lead: 0.18, bass: 0.5, swing_delta: -3, stereo: 0.45, saturation: 0.14, melodic_density: 0.22, fill_rate: 0.12 },
  }.freeze

  # Lead + scale_lead always available after intro so chord-tone arps can sit on top.
  ENSEMBLE_TIMELINE = {
    intro:     %i[ep warm texture],
    verse:     %i[ep warm texture lead scale_lead],
    hook:      %i[ep warm texture lead scale_lead],
    bridge:    %i[ep warm texture lead scale_lead],
    solo:      %i[ep warm lead scale_lead],
    breakdown: %i[warm texture lead],
    outro:     %i[ep warm texture lead scale_lead],
  }.freeze

  PERFORMERS = {
    yancey: {
      name: "James Yancey", kick_lag_ms: 8, snare_early_ms: -18, hat_late_ms: 22,
      velocity_spread: 0.14, gate_mul: 0.88, ghost_boost: 1.15,
    },
    questlove: {
      name: "Questlove", kick_lag_ms: 2, snare_early_ms: -8, hat_late_ms: 6,
      velocity_spread: 0.08, gate_mul: 0.95, ghost_boost: 1.35,
    },
    chris_dave: {
      name: "Chris Dave", kick_lag_ms: 14, snare_early_ms: -12, hat_late_ms: 28,
      velocity_spread: 0.18, gate_mul: 0.72, ghost_boost: 1.5,
    },
    karriem: {
      name: "Karriem Riggins", kick_lag_ms: 5, snare_early_ms: -14, hat_late_ms: 12,
      velocity_spread: 0.11, gate_mul: 0.9, ghost_boost: 1.25,
    },
    glasper: {
      name: "Robert Glasper", kick_lag_ms: 4, snare_early_ms: -6, hat_late_ms: 10,
      velocity_spread: 0.1, gate_mul: 1.08, ghost_boost: 0.95,
    },
    herbie: {
      name: "Herbie Hancock", kick_lag_ms: 3, snare_early_ms: -4, hat_late_ms: 8,
      velocity_spread: 0.09, gate_mul: 1.12, ghost_boost: 0.88,
    },
    thundercat: {
      name: "Thundercat", kick_lag_ms: 10, snare_early_ms: -10, hat_late_ms: 18,
      velocity_spread: 0.12, gate_mul: 0.82, ghost_boost: 1.1,
    },
    dilla: { name: "Dilla default", kick_lag_ms: 6, snare_early_ms: -12, hat_late_ms: 14,
             velocity_spread: 0.1, gate_mul: 0.92, ghost_boost: 1.2 },
  }.freeze

  # velocity_curve is an accent SHAPE, not a level. dilla_velocity multiplies the
  # role base by it per 16th, so a curve has to centre on 1.0: the contour says
  # which subdivision is emphasised, and DILLA_ROLE_VELOCITY_BASE alone says how
  # hard the kit hits.
  #
  # Every curve here centred on ~0.5 instead, which is not an accent at all --
  # it is a second, hidden gain stage attenuating the whole kit by ~8 dB on every
  # profile at once. Measured on a 16-bar donuts render: the loudest snare in the
  # take reached 0.261 against its 0.66 base, the loudest kick 0.180 against 0.49,
  # and the kit sat only +2.0 dB over the harmony bus. Because the scaling was
  # uniform across roles, it read as "no drums" rather than as a quiet kick --
  # cutting KICK_GAIN in half moved the presence band by 0.1 dB, since the snare
  # and hats were being held down by exactly the same factor.
  #
  # Each contour below is its original, divided by its own mean. Relative accent,
  # swing and ghost density are bit-for-bit what they were; only the missing 8 dB
  # comes back. Renormalising to 1.0 puts the kit +6.6 dB and its presence band
  # +6.3 dB, at +6.7 dB over the harmony bus.
  GROOVE_DNA = {
    donuts: {
      kick_offset_ms: [0, 6, 12, 18, 24], hat_offset_ms: [8, 14, 20, 26],
      swing: 61, ghost_density: 1.25, velocity_curve: [0.84, 1.04, 0.96, 1.16],
    },
    fantastic_vol2: {
      kick_offset_ms: [0, 4, 10, 16], hat_offset_ms: [6, 12, 18],
      swing: 58, ghost_density: 1.1, velocity_curve: [0.901, 1.033, 0.939, 1.127],
    },
    endtroducing: {
      kick_offset_ms: [0, 8, 14], hat_offset_ms: [10, 18, 24],
      swing: 54, ghost_density: 0.85, velocity_curve: [0.889, 1.022, 0.978, 1.111],
    },
    madvillainy: {
      kick_offset_ms: [0, 5, 11, 20], hat_offset_ms: [7, 15, 22],
      swing: 63, ghost_density: 1.4, velocity_curve: [0.862, 1.069, 0.948, 1.121],
    },
    cosmogramma: {
      kick_offset_ms: [0, 10, 18, 26], hat_offset_ms: [12, 20, 28],
      swing: 66, ghost_density: 1.15, velocity_curve: [0.871, 1.03, 0.99, 1.109],
    },
  }.freeze

  class MotifCell
    attr_reader :id, :degrees, :rhythm, :state

    STATES = %i[A A_prime A_double_prime].freeze

    def initialize(id:, degrees:, rhythm: [1.0, 0.5, 0.5, 1.0], state: :A)
      @id = id
      @degrees = degrees
      @rhythm = rhythm
      @state = state
    end

    def evolve!
      idx = STATES.index(@state) || 0
      @state = STATES[[idx + 1, STATES.length - 1].min]
      self
    end

    def degrees_for_playback
      case @state
      when :A then @degrees
      when :A_prime then @degrees.map { |d| d + 1 }
      when :A_double_prime then @degrees.reverse + @degrees.first(2)
      else @degrees
      end
    end

    def to_h
      { id: @id, degrees: @degrees, rhythm: @rhythm, state: @state.to_s }
    end

    def self.parse_state(raw)
      sym = raw.to_s.to_sym
      return sym if STATES.include?(sym)
      case raw.to_s
      when "A", "a" then :A
      when "A_prime", "A'", "a_prime" then :A_prime
      when "A_double_prime", "A''", "a_double_prime" then :A_double_prime
      else :A
      end
    end

    def self.from_h(h)
      new(id: h["id"] || h[:id], degrees: h["degrees"], rhythm: h["rhythm"] || [1.0, 0.5, 0.5, 1.0],
          state: parse_state(h["state"] || h[:state] || "A"))
    end
  end

  class Session
    attr_accessor :track, :performer, :groove_dna, :generation, :best_score
    attr_reader :motifs, :callbacks, :tension_curve, :critique_log, :arrangement

    def initialize(track: "timeless", performer: :yancey, groove_dna: :donuts, n_bars: 64)
      @track = track
      @performer = performer.to_sym
      @groove_dna = groove_dna.to_sym
      @generation = 0
      @best_score = 0.0
      @motifs = []
      @callbacks = []
      @critique_log = []
      @arrangement = build_arrangement(n_bars)
      @tension_curve = build_tension_curve(n_bars)
      seed_motifs!
    end

    def build_arrangement(n_bars)
      bars_per = (n_bars.to_f / ARRANGEMENT_FORM.length).ceil.clamp(4, 32)
      plan = []
      bar = 0
      ARRANGEMENT_FORM.each do |section|
        bars_per.times do
          break if bar >= n_bars
          plan << { bar:, section: }
          bar += 1
        end
      end
      while bar < n_bars
        plan << { bar:, section: :verse }
        bar += 1
      end
      plan
    end

    def build_tension_curve(n_bars)
      # Intro low → verse rise → hook peak → bridge dip → solo climb → breakdown valley → outro fade
      anchors = [0.18, 0.35, 0.72, 0.4, 0.55, 0.88, 0.32, 0.22]
      curve = []
      n_bars.times do |b|
        pos = b.to_f / [n_bars - 1, 1].max
        ai = pos * (anchors.length - 1)
        i0 = ai.floor
        i1 = [i0 + 1, anchors.length - 1].min
        frac = ai - i0
        curve << (anchors[i0] * (1 - frac) + anchors[i1] * frac).round(4)
      end
      curve
    end

    def seed_motifs!
      return unless @motifs.empty?
      rng = Random.new(stable_hash(@track))
      hook = MotifCell.new(id: "hook", degrees: [0, 2, 1, 3].first(rng.rand(3..4)),
                           rhythm: [1.0, 0.5, 0.5, 1.0])
      bass = MotifCell.new(id: "bass_motif", degrees: [0, 0, 2, 1], rhythm: [1.0, 1.0, 0.5, 0.5])
      @motifs = [hook, bass]
      @callbacks = [{ bar: 0, motif_id: "hook", state: :A },
                    { bar: 16, motif_id: "hook", state: :A_prime },
                    { bar: 32, motif_id: "hook", state: :A_double_prime },
                    { bar: 48, motif_id: "hook", state: :A_prime }]
    end

    def section_at(bar)
      entry = @arrangement.find { |e| e[:bar] == bar }
      entry ? entry[:section] : :verse
    end

    def profile_at(bar)
      ARRANGEMENT_PROFILES[section_at(bar)] || ARRANGEMENT_PROFILES[:verse]
    end

    def tension_at(bar)
      @tension_curve[bar.clamp(0, @tension_curve.length - 1)] || 0.5
    end

    def motif_for_bar(bar)
      cb = @callbacks.select { |c| c[:bar] <= bar }.max_by { |c| c[:bar] }
      return unless cb
      m = @motifs.find { |mot| mot.id == cb[:motif_id] }
      return m unless m
      MotifCell.new(id: m.id, degrees: m.degrees, rhythm: m.rhythm, state: cb[:state])
    end

    def performer_profile
      PERFORMERS[@performer] || PERFORMERS[:dilla]
    end

    def groove_profile
      GROOVE_DNA[@groove_dna] || GROOVE_DNA[:donuts]
    end

    def ensemble_roles(section = nil)
      section ||= :verse
      ENSEMBLE_TIMELINE[section] || ENSEMBLE_TIMELINE[:verse]
    end

    # A callback is identified by where it lands, which motif it recalls and in
    # which state, so registering the same one twice is not two callbacks.
    #
    # This appended unconditionally and the session is persisted, so the list grew
    # across every render the session survived: session.json reached 354 entries
    # holding 4 distinct callbacks. Scorer.score_plan reads the length, which is
    # what made the score meaningless (see the note there).
    def record_callback!(bar, motif_id, state)
      entry = { bar:, motif_id:, state: }
      return if @callbacks.include?(entry)

      @callbacks << entry
      m = @motifs.find { |mot| mot.id == motif_id }
      m&.evolve!
    end

    def mutate!(rng: Random.new(@generation + 1))
      @generation += 1
      @performer = PERFORMERS.keys.sample(random: rng)
      @groove_dna = GROOVE_DNA.keys.sample(random: rng)
      @motifs.each { |m| m.evolve! if rng.rand < 0.4 }
      @tension_curve = @tension_curve.map { |t| (t + rng.rand(-0.08..0.08)).clamp(0.05, 0.98).round(4) }
      self
    end

    def save!
      FileUtils.mkdir_p(PROJECT_DIR)
      payload = {
        track: @track, performer: @performer.to_s, groove_dna: @groove_dna.to_s,
        generation: @generation, best_score: @best_score,
        motifs: @motifs.map(&:to_h), callbacks: @callbacks.map { |c| c.transform_values(&:to_s) },
        tension_curve: @tension_curve,
        arrangement: @arrangement.map { |e| e.transform_values(&:to_s) },
        critique_log: @critique_log.last(20)
      }
      DillaFrozen.write_json(SESSION_PATH, payload)
      DillaFrozen.write_json(MOTIFS_PATH, @motifs.map(&:to_h))
      payload
    end

    # performer:/groove_dna:/track: are what the caller ASKED for, nil when it
    # asked for nothing. They win over the file.
    #
    # Before they existed this method took its identity entirely from
    # session.json, and composition_session! computed a performer and a groove
    # from ENV two lines before calling it and then discarded both. So a track
    # preset saying PERFORMER => yancey, or an operator typing PERFORMER=yancey,
    # was read, ignored, and reported back as whatever the last evolve happened
    # to leave on disk.
    #
    # Measured: a 26-track demo rendered 18 non-techno parts and every one of
    # them came out performer=questlove groove_dna=cosmogramma generation=59.
    # The drums varied across 22 presets and the tempo across 9 values, but the
    # pocket -- the thing those two knobs shape -- was identical on all of them.
    # That is most of why a catalogue of different progressions sounded like one
    # beat repeated.
    #
    # The track was wrong the same way: asking for semua_untuk_mu returned a
    # session whose track was neo_soul, because data["track"] came first.
    #
    # Everything else still comes from the file. The point is to keep the
    # evolved material -- motifs, callbacks, tension curve, generation -- while
    # letting the caller say who is playing it.
    def self.load!(default_track: "timeless", n_bars: 64, performer: nil, groove_dna: nil, track: nil)
      return new(track: track || default_track, performer: performer || :yancey,
                 groove_dna: groove_dna || :donuts, n_bars:) unless File.exist?(SESSION_PATH)

      data = JSON.parse(File.read(SESSION_PATH))
      s = new(track: track || data["track"] || default_track,
              performer: performer || (data["performer"] || "yancey").to_sym,
              groove_dna: groove_dna || (data["groove_dna"] || "donuts").to_sym, n_bars:)
      s.instance_variable_set(:@generation, data["generation"] || 0)
      s.instance_variable_set(:@best_score, data["best_score"] || 0.0)
      s.instance_variable_set(:@motifs, (data["motifs"] || []).map { |h| MotifCell.from_h(h) })
      # uniq on load, so a session file written before record_callback! deduped
      # heals itself the next time it is saved rather than carrying its duplicates
      # forward forever.
      s.instance_variable_set(:@callbacks, (data["callbacks"] || []).map do |c|
        h = c.transform_keys(&:to_sym)
        { bar: h[:bar].to_i, motif_id: h[:motif_id].to_s,
          state: MotifCell.parse_state(h[:state]) }
      end.uniq)
      s.instance_variable_set(:@tension_curve, data["tension_curve"] || s.build_tension_curve(n_bars))
      s.instance_variable_set(:@critique_log, data["critique_log"] || [])
      s
    rescue StandardError => e
      # Said out loud: a jam that silently starts over looks exactly like one
      # that loaded last night's work.
      warn "dilla: #{SESSION_PATH} unreadable (#{e.class}: #{e.message}) — starting a fresh session"
      # An interrupted save! (crash, kill -9, disk full) can leave session.json
      # truncated/invalid; a fresh session beats a hard crash on every
      # session/jam/evolve/critique/listen_loop command (same fallback style as
      # load_playlist_catalog, promoted_profiles.json, learned_engine.json).
      new(track: default_track, n_bars:)
    end

    # djb2, not String#hash — Ruby randomises String#hash per process, so this
    # seeded the motif pool from a different number on every run and the same
    # track never arranged the same twice.
    def stable_hash(text)
      text.to_s.each_byte.reduce(5381) { |a, b| ((a * 33) + b) % 4_294_967_296 }
    end
  end

  module Counterpoint
    module_function

    def adjust_voices(voices_hz)
      sorted = voices_hz.sort
      return sorted if sorted.length < 2
      out = sorted.dup
      (1...out.length).each do |i|
        out[i] = [out[i], out[i - 1] * 1.059].max if (out[i] - out[i - 1]).abs < 1.0
      end
      out
    end

    def neighbor_tone(root_hz, direction: :up)
      semitone = direction == :up ? 2.0**(2.0 / 12.0) : 2.0**(-2.0 / 12.0)
      root_hz * semitone
    end

  end

  module Conversation
    module_function

    # Returns offset seconds for answering voice per layer role.
    def answer_offset(role, beat_p)
      case role
      when :ep then beat_p * 0.5
      when :lead then beat_p * 1.0
      when :bass then beat_p * 0.25
      when :warm then beat_p * 2.0
      else beat_p * 0.75
      end
    end

    def turn_order(bar)
      %i[ep warm bass lead].rotate(bar % 4)
    end
  end

  module Critique
    module_function

    def analyze(report, session: nil, events: nil, progression_chords: nil, groove_meta: nil)
      lufs = report[:integrated_lufs] || report["integrated_lufs"]
      meta = groove_meta || events&.dig(:_groove_meta)
      groove = score_groove(events, meta:)
      chords = progression_chords || report[:progression_chords] || DillaHarmony.last_progression_chords
      harmony = if chords&.any?
                  DillaHarmony.score_beauty(chords)
                else
                  report[:harmony_score] || (72 + (session ? 8 : 0))
                end
      hook = session ? hook_score(session) : 55
      variation = session ? variation_score(session) : 50
      stereo = report.dig(:spectral_rms_db, :high) ? 88 : 75
      scores = { groove:, harmony:, hook:, variation:, stereo:, lufs: lufs_score(lufs) }
      recs = recommendations(scores, session, chords:)
      { scores:, recommendations: recs, overall: (scores.values.compact.sum / scores.length).round(1) }
    end

    def score_groove(events, meta: nil)
      DillaGrooveScore.analyze(events, meta:)[:score]
    end

    def hook_score(session)
      states = session.callbacks.map { |c| c[:state] }.uniq.length
      (50 + states * 12 + session.motifs.length * 5).clamp(30, 95)
    end

    def variation_score(session)
      (45 + session.generation * 3 + session.tension_curve.uniq.length * 0.5).round.clamp(30, 92)
    end

    # House target is quiet/warm (-20..-16 LUFS, per MASTER_LUFS_BY_STYLE),
    # not broadcast-loud (-14..-11) — that range was pulled down after direct
    # "way too loud" feedback (see dilla.rb MASTER_LUFS_BY_STYLE comment).
    # Scoring against the broadcast target penalized correctly-mastered output
    # on every generation. The advice below names the same window the score
    # uses, so a low score never recommends the loudness it just marked down.
    HOUSE_LUFS = (-20.0..-16.0).freeze

    def lufs_score(lufs, target: HOUSE_LUFS)
      return 70 unless lufs
      lufs = lufs.to_f
      target.cover?(lufs) ? 95 : 65
    end

    def recommendations(scores, session, chords: nil)
      recs = []
      recs << "Increase hook repetition — register more A/A'/A'' callbacks." if scores[:hook] < 65
      if chords&.any?
        recs.concat(DillaHarmony.recommendations(DillaHarmony.score_breakdown(chords)))
      elsif scores[:harmony] < 70
        recs << "Reduce pad masking — lower warm mix or high-pass pads in breakdown."
      end
      recs << "Move bass entrance earlier in verse sections." if session && session.profile_at(4)[:bass] < 0.7
      recs << "Add ghost-note density for pocket." if scores[:groove] < 75
      recs << "Push snare early / hats late for MPC pocket." if scores[:groove] < 80
      recs << "Thin hat grid on chop bars — let kick/snare breathe." if scores[:groove] < 72
      recs << "Widen stereo image on hook — raise lead/EP pan spread." if scores[:stereo] < 80
      recs << "Target LUFS #{HOUSE_LUFS.begin.to_i}..#{HOUSE_LUFS.end.to_i} for delivery." if scores[:lufs] && scores[:lufs] < 80
      recs << "Track feels balanced — evolve motifs for next pass." if recs.empty?
      recs.uniq
    end

    def print_report(critique)
      puts "── Producer critique ──"
      critique[:scores].each { |k, v| puts format("%-12s %s", "#{k}:", v) }
      puts "overall: #{critique[:overall]}"
      puts "Recommendations:"
      critique[:recommendations].each { |r| puts "  • #{r}" }
    end
  end

  module Scorer
    module_function

    def score_plan(session, cfg, n_bars)
      prof = session.profile_at(n_bars / 2)
      tension = session.tension_at(n_bars / 2)
      groove = session.groove_profile[:swing] / 70.0
      # Every term has to be bounded, or the final clamp(0.0, 1.0) hides the
      # overflow and every candidate scores exactly 1.0 -- which is what happened:
      # repetition was `callbacks.length * 0.08` against a session holding 354
      # callbacks, so that term alone contributed 4.25 of a maximum of 1.0 and
      # pick_best's max_by returned whichever candidate came first. Selection had
      # silently stopped working. Eight callbacks is full marks for hook
      # repetition; more is not better, and neither is a longer-lived session.
      novelty = (session.generation * 0.02).clamp(0.0, 1.0)
      repetition = (session.callbacks.length / 8.0).clamp(0.0, 1.0)
      release = (session.tension_curve.each_cons(2).count { |a, b| b < a } * 0.05).clamp(0.0, 1.0)
      voice_lead = cfg[:progression] ? 0.15 : 0.1
      (prof[:melodic_density] * 0.25 + tension * 0.2 + groove * 0.2 + repetition * 0.15 +
       novelty * 0.1 + release * 0.1 + voice_lead).clamp(0.0, 1.0)
    end

    def pick_best(candidates)
      candidates.max_by { |c| c[:score] }
    end
  end

  module Evolution
    module_function

    def dilla_pocket_style?(cfg)
      family = cfg[:style_family]
      return true if family == :dilla
      track = (cfg[:track] || ENV["TRACK"]).to_s.downcase
      track.match?(/dilla|donuts|timeless|slum|jaydee|yancey/)
    end

    # Two sets of weights, one per style, and they are exclusive. A scan of
    # literal defaults reports EVOLVE_HARMONY_W as 0.08 against 0.12 and
    # EVOLVE_GROOVE_W as 0.22 against 0.06, which reads as one knob answering two
    # ways when the branch is the answer: a dilla-pocket plan leans on groove and
    # lets harmony sit, and everything else derives its plan weight from the
    # harmony weight instead. `ruby dilla.rb knobs conflicts` prints the method
    # name beside each site so the pair reads as one method rather than two.
    def evolve_weights(cfg)
      if dilla_pocket_style?(cfg)
        return {
          plan: (ENV["EVOLVE_PLAN_W"] || 0.32).to_f,
          critique: (ENV["EVOLVE_CRITIQUE_W"] || 0.34).to_f,
          harmony: (ENV["EVOLVE_HARMONY_W"] || 0.08).to_f,
          groove: (ENV["EVOLVE_GROOVE_W"] || 0.22).to_f,
        }
      end

      hw = (ENV["EVOLVE_HARMONY_W"] || 0.12).to_f
      {
        plan: (50 - hw * 50) / 100.0,
        critique: 0.44,
        harmony: hw,
        groove: (ENV["EVOLVE_GROOVE_W"] || 0.06).to_f,
      }
    end

    def run(session:, cfg:, n_bars:, generations: 5, render_fn:)
      best = { score: -1.0, session:, path: nil }
      weights = evolve_weights(cfg)
      generations.times do |gen|
        session.generation = gen
        session.mutate!
        score = Scorer.score_plan(session, cfg, n_bars)
        path = render_fn.call(session)
        report = render_fn.respond_to?(:quality) ? render_fn.quality(path) : {}
        events = render_fn.respond_to?(:last_events) ? render_fn.last_events : nil
        critique = Critique.analyze(report, session:, events:,
                                    progression_chords: DillaHarmony.last_progression_chords)
        harmony_w = (critique[:scores][:harmony] || 70) * weights[:harmony]
        groove_w = (critique[:scores][:groove] || 70) * weights[:groove]
        total = (score * weights[:plan] * 100 + critique[:overall] * weights[:critique] +
                   harmony_w + groove_w).round(2)
        session.critique_log << { gen:, score: total, critique: critique[:scores] }
        if total > best[:score]
          best = { score: total, session:, path:, critique: }
          session.best_score = total
        end
        puts "gen #{gen}: score=#{total}"
      end
      session.save!
      best
    end
  end

  module ListeningLoop
    module_function

    # The loop converges on the window the critique scores in, HOUSE_LUFS.
    #
    # It aimed at -14.5..-10.5, broadcast loudness, which no style this engine
    # masters reaches: MASTER_LUFS_BY_STYLE runs -19 to -14, and the loop renders
    # render_dilla, whose target is -19. So every pass it measured was "too
    # quiet", every retry was pushed to -12.5 through MASTER_LUFS, and the take it
    # kept was the one the critique beside it marked down for loudness and the
    # operator had already called way too loud. One window means a pass the
    # critique accepts ends the loop, and a pass outside it is levelled to -18,
    # inside the house range rather than above every style in it.
    def converge(render_fn:, analyze_fn:, max_passes: 3, targets: {})
      targets = { lufs_min: Critique::HOUSE_LUFS.begin, lufs_max: Critique::HOUSE_LUFS.end,
                  groove_min: 75 }.merge(targets)
      path = nil
      max_passes.times do |pass|
        path = render_fn.call(pass)
        report = analyze_fn.call(path)
        critique = Critique.analyze(report)
        lufs = report[:integrated_lufs] || report["integrated_lufs"]
        groove = critique[:scores][:groove]
        puts "pass #{pass + 1}: LUFS=#{lufs} groove=#{groove}"
        break if lufs && lufs.to_f >= targets[:lufs_min] && lufs.to_f <= targets[:lufs_max] && groove >= targets[:groove_min]
        apply_drum_vol!((resolved_drum_mix_weight + 0.02)) if groove < targets[:groove_min]
        aim_master_loudness!(lufs, targets)
      end
      path
    end

    # A pass outside the loudness window aims the next one at the window's
    # middle through MASTER_LUFS, the knob normalise_master! sets the render's
    # level from. Raising HARM_VOL by 0.05, which the loop did before, moved
    # nothing: HARM_VOL is read only by build_harmony_loud, which this loop never
    # calls, and loudnorm at the end of render_dilla flattens a harmony gain
    # anyway. That write also raised TypeError, because ENV takes strings, so the
    # first quiet pass ended the command. The middle rather than the edge,
    # because a limiter-bound master lands a little under what it was asked for.
    def aim_master_loudness!(lufs, targets)
      return unless lufs
      return if lufs.to_f.between?(targets[:lufs_min], targets[:lufs_max])

      ENV["MASTER_LUFS"] = ((targets[:lufs_min] + targets[:lufs_max]) / 2.0).round(1).to_s
    end
  end
end

# Theory-grounded progression scoring -- the harmonic counterpart to
# DillaGrooveScore (rhythm). Every metric here is derived from voice-leading/
# functional-harmony theory (see lib/harmony.rb's own operators:
# common-tone retention, contrary motion, circle-of-fifths bias), not from
# similarity to any named track or producer. Mirrors DillaGrooveScore's shape
# (analyze -> {score:, breakdown:}) so both can feed the same report/recommend
# pipeline.
module DillaHarmonyScore
  module_function

  def analyze(pads)
    chords = Array(pads).select { |c| c.is_a?(Hash) && c[:hz]&.any? }
    return { score: 70, breakdown: {} } if chords.length < 2

    transitions = chords.each_cons(2).map { |a, b| transition_metrics(a, b) }

    vl = transitions.map { |t| t[:voice_leading_semitones] }
    ct = transitions.map { |t| t[:common_tone_ratio] }
    contrary = transitions.count { |t| t[:contrary_motion] }
    strong_root = transitions.count { |t| t[:strong_root_motion] }
    oblique = transitions.count { |t| t[:oblique_motion] }
    root_moves = transitions.map { |t| t[:root_motion_semitones] }
    spreads = chords.map { |c| chord_span_semitones(c) }

    avg_vl = vl.sum / vl.length
    avg_ct = ct.sum / ct.length
    contrary_ratio = contrary.to_f / transitions.length
    strong_root_ratio = strong_root.to_f / transitions.length
    oblique_ratio = oblique.to_f / transitions.length
    avg_root_motion = root_moves.sum / root_moves.length
    spread_var = variance(spreads)

    # Smoother average voice-leading movement scores higher (Bach-style
    # stepwise preference), but zero movement (static chords) isn't "smooth,"
    # it's dead -- 1-3 semitones/voice is the actual "smooth" band.
    score = 60.0
    score += smoothness_points(avg_vl)
    score += [avg_ct * 20, 16].min
    score += 8 if contrary_ratio.between?(0.2, 0.7)
    score += 6 if strong_root_ratio.between?(0.25, 0.75)
    # Oblique motion earns its own points. A structure held while the bass
    # walks under it is a technique, not a failure to move -- and with no term
    # for it the scorer could only read it as absent voice leading.
    score += 7 if oblique_ratio.between?(0.15, 0.6)
    score -= 6 if spread_var > 30 # register discipline: chords shouldn't randomly leap span

    breakdown = {
      avg_voice_leading_semitones: avg_vl.round(3),
      avg_common_tone_ratio: avg_ct.round(3),
      avg_root_motion_semitones: avg_root_motion.round(3),
      oblique_motion_ratio: oblique_ratio.round(3),
      contrary_motion_ratio: contrary_ratio.round(3),
      strong_root_motion_ratio: strong_root_ratio.round(3),
      register_spread_variance: spread_var.round(3),
      transitions: transitions.length,
    }

    { score: score.round.clamp(30, 98), breakdown: }
  end

  # A chord here carries its bass separately from its upper voices:
  #
  #   { name:, hz: [upper voices], bass_hz: <the root under them>, theory: }
  #
  # Everything below used to read :hz alone and take its lowest note as the bass,
  # which is not the bass -- it is the bottom of the upper structure. The comment
  # over strong_root_motion? even said it was using the bass note while the code
  # used a_notes.min, so the instrument disagreed with its own description.
  #
  # That mattered more than a naming slip. A slash chord or an upper triad over a
  # moving root is a structure held still while the bass walks underneath, and
  # measuring it without the bass reports the opposite of what it is: the root
  # motion vanishes and the upper voices, re-voiced to stay in register, read as
  # leaps. upper_triad_tower scored worst of all 401 progressions on exactly this.
  def voices_of(chord)
    upper = Array(chord[:hz]).map { |hz| DillaHarmony.hz_to_midi(hz.to_f).round }.sort
    bass = chord[:bass_hz].to_f.positive? ? DillaHarmony.hz_to_midi(chord[:bass_hz].to_f).round : upper.first
    # Drop a duplicate of the bass out of the upper set so it is not counted as
    # both the root and a voice above it.
    [bass, upper.reject { |n| n == bass }]
  end

  def transition_metrics(a, b)
    a_bass, a_upper = voices_of(a)
    b_bass, b_upper = voices_of(b)
    a_upper = [a_bass] if a_upper.empty?
    b_upper = [b_bass] if b_upper.empty?
    {
      # Upper voices only. The bass is a separate line with its own logic; adding
      # its movement into the average is what made held structures look like leaps.
      voice_leading_semitones: voice_leading_distance(a_upper, b_upper),
      root_motion_semitones: ((b_bass - a_bass).abs % 12).to_f,
      common_tone_ratio: common_tone_ratio(a_upper, b_upper),
      contrary_motion: contrary_motion?(a_bass, a_upper, b_bass, b_upper),
      oblique_motion: oblique_motion?(a_bass, a_upper, b_bass, b_upper),
      strong_root_motion: strong_root_motion?(a_bass, b_bass),
    }
  end

  # Nearest-neighbor voice pairing (not fixed SATB index -- chord voicings here
  # don't guarantee equal voice counts), average movement per matched pair.
  def voice_leading_distance(a_notes, b_notes)
    return 0.0 if a_notes.empty? || b_notes.empty?

    a_notes.sum { |n| b_notes.map { |m| (m - n).abs }.min }.to_f / a_notes.length
  end

  def common_tone_ratio(a_notes, b_notes)
    return 0.0 if a_notes.empty? || b_notes.empty?

    a_pc = a_notes.map { |n| n % 12 }.uniq
    b_pc = b_notes.map { |n| n % 12 }.uniq
    shared = (a_pc & b_pc).length
    shared.to_f / [a_pc.length, b_pc.length].min
  end

  # The real bass against the centre of the structure above it, rather than the
  # bottom and top of one stack. Two independent lines moving apart is what
  # contrary motion means; the outer notes of a single voicing moving apart is
  # usually just a re-voicing.
  def contrary_motion?(a_bass, a_upper, b_bass, b_upper)
    bass_delta = b_bass - a_bass
    upper_delta = centroid(b_upper) - centroid(a_upper)
    bass_delta != 0 && upper_delta.abs > 0.25 && (bass_delta <=> 0) != (upper_delta <=> 0)
  end

  # Oblique motion: one line moves while the other holds. This is the pedal, the
  # slash chord and the upper structure over a walking root -- the sound the old
  # scorer had no term for at all, and therefore scored as failure.
  def oblique_motion?(a_bass, a_upper, b_bass, b_upper)
    bass_moved = (b_bass - a_bass).abs >= 1
    upper_moved = (centroid(b_upper) - centroid(a_upper)).abs > 0.5
    bass_moved != upper_moved
  end

  def centroid(notes) = notes.empty? ? 0.0 : notes.sum.to_f / notes.length

  # Root motion of a 4th or 5th is the circle-of-fifths backbone. Taken from the
  # chord's own bass_hz, which is what the comment here always claimed.
  def strong_root_motion?(a_bass, b_bass)
    [5, 7].include?((b_bass - a_bass).abs % 12)
  end

  def chord_span_semitones(chord)
    notes = Array(chord[:hz]).map { |hz| DillaHarmony.hz_to_midi(hz.to_f) }
    return 0.0 if notes.empty?

    notes.max - notes.min
  end

  def smoothness_points(avg_vl)
    case avg_vl
    when 0...1 then 4.0 # near-static -- some credit, but not the max
    when 1...3 then 14.0 # the actual "smooth voice-leading" band
    when 3...5 then 8.0
    else [14.0 - (avg_vl - 5), 0].max
    end
  end

  def variance(values)
    return 0.0 if values.length < 2

    mean = values.sum / values.length
    values.sum { |v| (v - mean)**2 } / values.length
  end
end

# Chord-harmonic arp layer — arpeggiates voiced pad tones + extensions,
# voice-led across changes. Scale passing tones stay on scale_lead stem.
module DillaHarmonyLead
  PAD_REGISTER_CEILING = 76.0
  LEAD_REGISTER_LOW = 58.0
  LEAD_REGISTER_HIGH = 92.0

  EXTENSION_IV = {
    "maj9" => [2, 4], "m9" => [2, 5], "maj7" => [4], "m7" => [5, 10],
    "7" => [4, 10], "m11" => [2, 5, 7], "maj6" => [4, 9], "m6" => [5, 9],
    "9" => [2, 4], "11" => [2, 5, 7], "13" => [2, 4, 9],
  }.freeze

  module_function

  def normalized_symbol(name)
    name.to_s.sub(/_pedal\z/, "").sub(/_t\d+\z/, "").downcase.gsub(/low\z/, "")
  end

  def extension_semitones(sym)
    base = sym.gsub(%r{/.*\z}, "")
    EXTENSION_IV.each do |suffix, ivs|
      return ivs if base.end_with?(suffix) || base == suffix
    end
    return [2, 4] if base.include?("maj9") || base.include?("m9")
    return [4] if base.include?("maj7") || base.match?(/7\z/)
    [2]
  end

  def voice_lead_arp_targets(tones_hz, prev_chord)
    return tones_hz unless prev_chord && prev_chord[:hz]&.any?
    prev_top = DillaHarmony.hz_to_midi(prev_chord[:hz].max)
    tones_hz.sort_by do |hz|
      m = DillaHarmony.hz_to_midi(hz)
      (m - prev_top).abs + (m < prev_top ? 4.0 : 0.0)
    end
  end

  def harmonic_arp_tones_for_chord(chord, prev_chord: nil, mode: :hybrid)
    return [] unless chord && chord[:hz]&.any?

    sym = normalized_symbol(chord[:name])
    tones = chord[:hz].sort.dup
    root_midi = DillaHarmony.hz_to_midi(tones.first).floor
    extension_semitones(sym).each do |iv|
      midi = root_midi + iv
      midi += 12 while midi < LEAD_REGISTER_LOW
      tones << DillaHarmony.midi_to_hz(midi) if midi <= LEAD_REGISTER_HIGH
    end
    tones = voice_lead_arp_targets(tones.uniq, prev_chord) if prev_chord
    floor = DillaHarmony.hz_to_midi(tones.max) >= PAD_REGISTER_CEILING ? PAD_REGISTER_CEILING : LEAD_REGISTER_LOW
    tones.filter_map do |hz|
      m = DillaHarmony.hz_to_midi(hz)
      next if m < floor - 2
      hz
    end.uniq.sort
  end

  def arp_style_for_change(prev_chord, chord, insight: nil)
    return :major_third_cycle_full unless prev_chord && chord
    prev_sym = normalized_symbol(prev_chord[:name])
    sym = normalized_symbol(chord[:name])
    return :quint_spread if sym.include?("eb") && prev_sym.include?("bb")
    return :call if insight && insight[:notation].to_s.include?("V")
    return :motif if prev_sym == sym
    prev_iv = chord_intervals_simple(prev_chord)
    cur_iv = chord_intervals_simple(chord)
    shared = (prev_iv & cur_iv).length
    shared >= 3 ? :motif : :quint_spread
  end

  def chord_intervals_simple(chord)
    midis = chord[:hz].map { |h| DillaHarmony.hz_to_midi(h) }.sort
    root = midis.first
    midis.map { |m| ((m - root) % 12).round }.uniq
  end

  def section_density(section, progress)
    base = case section
           when :intro then 0.42
           when :breakdown then 0.52
           when :turn then 0.88
           when :build then 0.95
           when :outro then 0.58
           else 0.78
           end
    base * (progress < 0.1 ? 0.72 : 1.0)
  end

  def passing_tone_hz(chord, step, rng)
    return unless chord && chord[:hz]&.any?
    return if rng.rand > 0.14
    scale = chord_scale_semitones(chord)
    root = DillaHarmony.hz_to_midi(chord[:hz].min).floor
    semi = scale[(step + rng.rand(0..2)) % scale.length]
    midi = root + semi + 12
    return unless midi.between?(LEAD_REGISTER_LOW, LEAD_REGISTER_HIGH)
    DillaHarmony.midi_to_hz(midi)
  end

  # Chord → scale degrees the lead may use, 0-11 from the chord root.
  #
  # This decides every note every lead layer plays: dilla.rb's own
  # chord_scale_semitones delegates here, and scale_tones_for_chord builds the
  # melodic lead, the scale arp and the harmony arp out of the result. It was
  # wrong on the single most common chord in the catalogue.
  #
  # The old version tested `name.match?(/7\z/)` for dominant BEFORE it tested
  # for major, against the whole symbol including its root letter. "cmaj7" ends
  # in a 7, so every major-seventh chord matched the dominant branch and never
  # reached the major one:
  #
  #   Cmaj7 -> [0,2,4,5,7,9,10]   Mixolydian. Flat 7.
  #
  # That hands the lead a Bb to play over a Cmaj7 whose defining tone is B --
  # a minor second on the chord's most exposed note, on every maj7 in every
  # progression. Minor chords took the earlier branch and were fine, which is
  # exactly the shape of the complaint: the pads were right and the lead was
  # fighting them.
  #
  # Dominant 13ths failed the other way. "c13" matches neither /7\z/ nor "maj",
  # so it fell through to the Ionian default and put a natural 7 over a chord
  # whose seventh is flat.
  #
  # Two changes stop both. The root letter is stripped first, so the suffix is
  # matched on its own and "maj7" can never look like a dominant. And the order
  # runs most-specific to least, with the fallthrough last rather than a
  # dominant rule sitting in front of it.
  #
  # The 4th is omitted from the major and dominant sets. The perfect 11th is the
  # avoid note over both -- it sits a semitone above the major 3rd and buries it
  # -- and standard practice is to drop it or sharpen it to #11. Minor keeps its
  # 4th, where the 11th is consonant and is half of what makes m11 voicings
  # sound the way they do. Chords that ask for the bright colour (lyd, maj9,
  # maj13) get the #11 instead of nothing.
  DORIAN = [0, 2, 3, 5, 7, 9, 10].freeze
  AEOLIAN = [0, 2, 3, 5, 7, 8, 10].freeze
  LOCRIAN = [0, 2, 3, 5, 6, 8, 10].freeze
  PHRYGIAN = [0, 1, 3, 5, 7, 8, 10].freeze
  LYDIAN = [0, 2, 4, 6, 7, 9, 11].freeze
  IONIAN_NO4 = [0, 2, 4, 7, 9, 11].freeze
  MIXO_NO4 = [0, 2, 4, 7, 9, 10].freeze

  def chord_quality(name)
    # Slash bass says nothing about the scale -- Bbm/E is still minor -- and the
    # root letter is what made "maj7" testable as a dominant.
    normalized_symbol(name).sub(%r{/.*\z}, "").sub(/\A[a-g][#b]?/, "")
  end

  # The five notes major and minor agree on: root, second, fourth, fifth,
  # flat seventh. Missing from it are the third and the sixth -- precisely the
  # two degrees that differ between the modes. A line drawn from these notes is
  # consonant over a loop whichever mode it turns out to be in.
  #
  # It is also, not by accident, the pentatonic scale that most of the world's
  # folk music is built from, so playing inside it costs nothing musically.
  NEUTRAL_PENTATONIC = [0, 2, 5, 7, 10].freeze

  def chord_scale_semitones(chord)
    # Set when the key detector read a root it trusts and a mode it does not.
    # See the harmonic guard in dilla.rb.
    return NEUTRAL_PENTATONIC if ENV["MODE_UNCERTAIN"] == "1"

    resolve_avoid_notes(scale_from_symbol(chord), chord)
  end

  def scale_from_symbol(chord)
    q = chord_quality(chord[:name])

    return LOCRIAN if q.include?("dim") || q.include?("m7b5") || q.include?("o7")
    return PHRYGIAN if q.include?("phry")
    # Minor before anything that could match a digit. "maj" is excluded so
    # "maj7" cannot be read as m-something.
    # Dorian is the default for minor, not Aeolian, and the clash check is what
    # settled it rather than taste. Aeolian's b6 sits a semitone above the 5th,
    # so over Am7 the lead gets an F to play against the chord's E -- the same
    # avoid-note shape that made maj7 fail, one degree along. Dorian's natural 6
    # has no note above a chord tone at all, and it is the minor sound this
    # idiom actually uses. AEOLIAN is kept for a chord that asks for the b6.
    if q.include?("aeol") || q.include?("nat_minor")
      return AEOLIAN
    elsif q.start_with?("dor") || (q.start_with?("m") && !q.start_with?("maj")) ||
          q.include?("min") || q.start_with?("-")
      return DORIAN
    end
    return LYDIAN if q.include?("lyd") || q.include?("maj9") || q.include?("maj13") || q.include?("#11")
    return IONIAN_NO4 if q.include?("maj") || q.include?("add9") || q.match?(/\A6?\z/)
    return MIXO_NO4 if q.match?(/\A(7|9|11|13)/) || q.include?("dom") || q.include?("mix") || q.include?("alt")

    IONIAN_NO4
  end

  # The chord's own voicing, as semitones from its root.
  #
  # The name is a label and the voicing is the fact. Bm7b5 as registered here
  # sounds a b9 that its symbol never mentions, and a scale chosen from the
  # symbol alone cannot know that.
  def voiced_semitones(chord)
    hz = chord[:hz]
    return [] unless hz.is_a?(Array) && hz.any?

    pc = root_pitch_class(chord[:name])
    return [] unless pc

    hz.map { |h| ((69 + (12 * Math.log2(h / 440.0))).round - pc) % 12 }.uniq
  end

  LETTER_PC = { "c" => 0, "d" => 2, "e" => 4, "f" => 5, "g" => 7, "a" => 9, "b" => 11 }.freeze

  def root_pitch_class(name)
    # Before the slash: an upper structure over a pedal is still rooted on the
    # upper structure, which is what chord_root_pc in dilla.rb decides too.
    m = normalized_symbol(name).split("/").first.to_s.match(/\A([a-g])([#b]?)/)
    return unless m && (base = LETTER_PC[m[1]])

    (base + (m[2] == "#" ? 1 : 0) - (m[2] == "b" ? 1 : 0)) % 12
  end

  # Drop scale degrees that sit a semitone ABOVE a note the chord is sounding.
  #
  # That interval is the one that reads as a mistake: the scale tone buries the
  # chord tone under it and the ear hears the clash rather than the colour. A
  # semitone BELOW is a leading tone and is left alone, because approaching a
  # chord tone from underneath is how melodies work.
  #
  # Doing this against the voicing rather than the symbol is what catches the
  # three chords the symbol-driven table still got wrong -- C7b9, E7b9 and
  # Bm7b5 all voice a b9 and were being handed the natural 9 above it.
  #
  # Only ever removes, never substitutes, and refuses to strip a scale below
  # four notes: a lead with nothing left to play is worse than one avoid note.
  MIN_SCALE_TONES = 4

  def resolve_avoid_notes(scale, chord)
    tones = voiced_semitones(chord)
    return scale if tones.empty?

    kept = scale.reject { |s| !tones.include?(s) && tones.include?((s - 1) % 12) }
    kept.length >= MIN_SCALE_TONES ? kept : scale
  end
end

# Bach + J Dilla as Ruby runtime theory — not named “styles”, but operators
# on chord arrays at render time.
#
# Bach (species / thoroughbass practice, simplified for pad voicings):
#   - prefer stepwise upper-voice motion
#   - avoid parallel perfect fifths/octaves between outer voices
#   - contrary motion when bass leaps
#   - circle-of-fifths bias for functional chains
#
# Dilla (neo-soul / MPC harmony practice):
#   - common-tone retention between chords
#   - slash / pedal bass color without reharmonizing the upper structure away
#   - delayed resolution (keep tension tones an extra beat’s worth of voicing)
#   - rootless upper structures when density allows
#
# Uses major_third_cycle_full / head_music when present (DillaMusicGems); otherwise pure math.
module DillaTheoryRuntime
  module_function

  def enabled?
    ENV.fetch("THEORY_RUNTIME", "1") != "0"
  end

  def bach_mode?
    ENV["THEORY_BACH"] == "1" ||
      ENV["TRACK"].to_s.match?(/bach|baroque|circle|fugue/i) ||
      ENV["VOICING"].to_s == "drop2"
  end

  def dilla_mode?
    ENV.fetch("THEORY_DILLA", "1") != "0"
  end

  # Main entry — mutate a progression of {name:, hz:} chords.
  def refine_progression!(chords, cfg: {})
    return chords unless enabled? && chords.is_a?(Array) && chords.length >= 2

    out = chords.map { |c| c.is_a?(Hash) ? c.dup : c }
    out = dilla_common_tone_lock!(out) if dilla_mode?
    out = dilla_slash_pedal_bias!(out, cfg) if dilla_mode?
    out = bach_voice_lead!(out) if bach_mode? || ENV["THEORY_BACH"] == "1"
    out = bach_avoid_parallel_outer!(out) if bach_mode? || ENV.fetch("THEORY_PARALLELS", "1") != "0"
    out = annotate_theory!(out)
    out
  rescue StandardError => e
    warn "theory_runtime: #{e.message}" if ENV["DILLA_DEBUG"]
    chords
  end

  # Keep shared pitch classes between adjacent chords (Dilla/neo-soul glue).
  def dilla_common_tone_lock!(chords)
    (1...chords.length).each do |i|
      prev = Array(chords[i - 1][:hz]).map { |hz| hz_to_pc(hz) }
      curr_hz = Array(chords[i][:hz]).map(&:to_f).sort
      next if curr_hz.length < 2 || prev.empty?

      shared = prev & curr_hz.map { |hz| hz_to_pc(hz) }
      next if shared.empty?

      # Nudge nearest voice toward a common tone (same pitch class, closest octave).
      target_pc = shared.first
      best_j = nil
      best_cost = 1e9
      curr_hz.each_with_index do |hz, j|
        pc = hz_to_pc(hz)
        cost = [(pc - target_pc).abs, 12 - (pc - target_pc).abs].min
        if cost < best_cost
          best_cost = cost
          best_j = j
        end
      end
      next unless best_j && best_cost.positive? && best_cost <= 3

      midi = hz_to_midi(curr_hz[best_j])
      want = midi - ((midi.round - target_pc) % 12)
      # Snap to nearest pitch-class match within ±7 semitones.
      delta = ((target_pc - (midi.round % 12) + 6) % 12) - 6
      curr_hz[best_j] = midi_to_hz(midi + delta) if delta.abs <= 7
      chords[i] = chords[i].merge(hz: curr_hz.sort)
    end
    chords
  end

  # Prefer keeping lowest voice as pedal/slash color when progression is static-ish.
  def dilla_slash_pedal_bias!(chords, cfg)
    return chords if chords.length < 3

    pedal = Array(chords.first[:hz]).map(&:to_f).min
    return chords unless pedal&.positive?

    # Only apply light pedal on curated soul tracks / when THEORY_PEDAL=1.
    track = (cfg[:track] || ENV["TRACK"]).to_s
    allow = ENV["THEORY_PEDAL"] == "1" || track.match?(/neo_soul|dilla|untitled|slash|get_dis|donut|erykah/i)
    return chords unless allow

    (1...chords.length).each do |i|
      hz = Array(chords[i][:hz]).map(&:to_f).sort
      next if hz.length < 3

      # Replace lowest with pedal octave near original bass.
      bass = hz.first
      target = pedal
      target *= 2 while target * 2 < bass * 0.85
      target /= 2 while target > bass * 1.25 && target > 40
      hz[0] = target
      chords[i] = chords[i].merge(hz: hz.sort, bass_hz: target)
    end
    chords
  end

  # Smooth upper-voice motion (Bach-ish): minimize total stepwise distance.
  def bach_voice_lead!(chords)
    (1...chords.length).each do |i|
      prev = Array(chords[i - 1][:hz]).map(&:to_f).sort
      curr = Array(chords[i][:hz]).map(&:to_f).sort
      next if prev.empty? || curr.empty?

      n = [prev.length, curr.length].min
      led = Array.new(n)
      used = {}
      # Greedy: assign each previous voice to nearest unused current pitch-class tone.
      prev.first(n).each_with_index do |phz, vi|
        best = nil
        best_d = 1e9
        curr.each_with_index do |chz, ci|
          next if used[ci]
          d = (hz_to_midi(chz) - hz_to_midi(phz)).abs
          if d < best_d
            best_d = d
            best = ci
          end
        end
        if best
          used[best] = true
          # Octave-fold toward previous voice.
          pm = hz_to_midi(phz)
          cm = hz_to_midi(curr[best])
          while cm - pm > 6
            cm -= 12
          end
          while pm - cm > 6
            cm += 12
          end
          led[vi] = midi_to_hz(cm.clamp(DillaHarmony::PAD_MIDI_MIN, DillaHarmony::PAD_MIDI_MAX))
        end
      end
      led.compact!
      next if led.length < 2

      # Keep any unused upper extensions.
      extras = curr.reject.with_index { |_, ci| used[ci] }
      chords[i] = chords[i].merge(hz: (led + extras).sort.last([led.length + extras.length, 5].min))
    end
    chords
  end

  # Soften parallel 5ths/8ves between bass and soprano by nudging soprano.
  def bach_avoid_parallel_outer!(chords)
    (1...chords.length).each do |i|
      a = Array(chords[i - 1][:hz]).map(&:to_f).sort
      b = Array(chords[i][:hz]).map(&:to_f).sort
      next if a.length < 2 || b.length < 2

      ab, as_ = a.first, a.last
      bb, bs = b.first, b.last
      int_a = (hz_to_midi(as_) - hz_to_midi(ab)).round % 12
      int_b = (hz_to_midi(bs) - hz_to_midi(bb)).round % 12
      next unless [0, 7].include?(int_a) && int_a == int_b

      # Parallel perfect — drop soprano a whole step if possible.
      bs_m = hz_to_midi(bs) - 2
      b[-1] = midi_to_hz(bs_m.clamp(DillaHarmony::PAD_MIDI_MIN, DillaHarmony::PAD_MIDI_MAX))
      chords[i] = chords[i].merge(hz: b.sort)
    end
    chords
  end

  def annotate_theory!(chords)
    symbols = chords.map { |c| c[:name].to_s }
    insight = nil
    if defined?(DillaMusicGems) && DillaMusicGems.respond_to?(:progression_analysis)
      insight = DillaMusicGems.progression_analysis(symbols)
    end
    chords.each_with_index do |c, i|
      c[:theory] = {
        pc: Array(c[:hz]).map { |hz| hz_to_pc(hz) },
        insight: i.zero? ? insight : nil,
      }
    end
    chords
  end

  # Delegates to DillaHarmony's canonical conversions (harmony.rb,
  # required before this file) so the two engines can't drift -- they used
  # to be reimplemented here with a different midi_to_hz rounding than
  # DillaHarmony's, so a chord tone processed by each carried different
  # precision and could fail exact-hz comparisons downstream.
  def hz_to_midi(hz)
    return 60.0 if hz.to_f <= 0
    DillaHarmony.hz_to_midi(hz.to_f)
  end

  def midi_to_hz(midi)
    DillaHarmony.midi_to_hz(midi.to_f)
  end

  def hz_to_pc(hz)
    hz_to_midi(hz).round % 12
  end
end
