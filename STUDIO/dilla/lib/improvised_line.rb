# frozen_string_literal: true

require_relative "devices"

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
