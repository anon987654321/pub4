# frozen_string_literal: true

require "fileutils"

# Playing a record instead of repeating it.
#
# Until now a sampled track worked like this: take a few bars off a record,
# match it to the tempo, and run it round and round for the length of the song.
# That is a loop. It is not what the producers this engine is named after did.
#
# Dilla cut a record into pieces, laid the pieces across the sixteen pads of an
# MPC, and played a NEW line out of them -- the original's notes, in an order
# the original never had. The bassline on "Don't Cry" is not on the Escorts
# record he took it from; it is him playing their notes back in his own order.
# That is a flip, and the difference between the two is the difference between
# borrowing a record and playing one.
#
# This module does that. In four steps:
#
#   1. CUT.       Find where the notes start and cut there.
#   2. LISTEN.    Work out what pitch each piece is.
#   3. ARRANGE.   Choose, for every beat of the new track, the piece whose pitch
#                 fits the chord underneath it.
#   4. PLAY.      Lay the chosen pieces onto the beat, slightly off the grid,
#                 the way a hand playing pads is slightly off the grid.
#
# The result is written out as an ordinary audio file, which the engine then
# treats exactly as it treated the loop -- so everything downstream, the key
# handling and the bridges and the drum carving, works unchanged.
module SampleFlip
  RATE = 44_100

  # Pieces shorter than this are clicks rather than notes, and pieces longer
  # than this are phrases rather than pieces -- a whole bar of the original,
  # which would put us back to looping.
  MIN_SLICE_SEC = 0.09
  MAX_SLICE_SEC = 1.60

  # An MPC has sixteen pads. Keeping to that is not nostalgia: a handful of
  # strong pieces played in a good order beats fifty weak ones, and the
  # arranging step below gets to be choosier when the pool is small.
  MAX_SLICES = 16
  MIN_SLICES = 4

  # How far a piece may be retuned to reach the note we want. Beyond about four
  # semitones a varispeed shift also stretches the piece audibly and the
  # original instrument starts to sound like a different instrument -- which is
  # sometimes the point, but not by accident.
  MAX_SHIFT_SEMITONES = 4

  # Two milliseconds of fade at each end. Cutting a waveform at a non-zero
  # point leaves a step, and a step is a click. This is the shortest fade that
  # reliably removes it while staying inaudible as a fade.
  EDGE_FADE_SEC = 0.002

  # Sixteenth notes. The grid a sampler sequences on.
  STEPS_PER_BAR = 16

  module_function

  # ---------------------------------------------------------------- decoding

  # Reads an audio file as two arrays of numbers between -1 and 1, one per
  # channel. Everything below works on these arrays rather than on the file.
  def decode(path, rate: RATE)
    raw = IO.popen(
      ["ffmpeg", "-v", "quiet", "-i", path, "-ac", "2", "-ar", rate.to_s,
       "-f", "s16le", "-acodec", "pcm_s16le", "-"],
      "rb", &:read
    )
    return [[], []] if raw.nil? || raw.empty?

    samples = raw.unpack("s<*")
    left = Array.new(samples.length / 2)
    right = Array.new(samples.length / 2)
    i = 0
    while i < left.length
      left[i] = samples[i * 2] / 32_768.0
      right[i] = samples[(i * 2) + 1] / 32_768.0
      i += 1
    end
    [left, right]
  end

  # Writes two channel arrays back out as a wav, by handing raw numbers to
  # ffmpeg and letting it put the header on. Hand-rolling a RIFF header is
  # twenty lines that can be wrong in ways that are tedious to find.
  def encode!(left, right, dest, rate: RATE)
    FileUtils.mkdir_p(File.dirname(dest))
    interleaved = Array.new(left.length * 2)
    i = 0
    while i < left.length
      interleaved[i * 2] = clamp16(left[i])
      interleaved[(i * 2) + 1] = clamp16(right[i])
      i += 1
    end
    IO.popen(
      ["ffmpeg", "-y", "-v", "quiet", "-f", "s16le", "-ar", rate.to_s, "-ac", "2",
       "-i", "-", "-c:a", "pcm_s16le", dest],
      "wb"
    ) { |io| io.write(interleaved.pack("s<*")) }
    dest
  end

  def clamp16(value)
    scaled = (value * 32_767.0).round
    scaled.clamp(-32_768, 32_767)
  end

  # ------------------------------------------------------------------ cutting

  # Finds where notes begin.
  #
  # A note beginning is a sudden rise in level. We measure the loudness of every
  # five-millisecond window, then look for windows that are markedly louder than
  # the recent past. "Markedly" is measured against the piece's own median
  # rather than a fixed number, because these are chopped from different records
  # at different levels and a threshold that suits one finds nothing in another.
  ONSET_WINDOW_SEC = 0.005
  ONSET_LIFT = 1.8      # times the running average
  ONSET_FLOOR_RATIO = 0.10  # ignore anything this quiet relative to the peak

  def onsets(mono, rate: RATE)
    win = (ONSET_WINDOW_SEC * rate).to_i
    return [] if win < 1 || mono.length < win * 8

    # Loudness per window.
    levels = []
    idx = 0
    while idx + win <= mono.length
      sum = 0.0
      j = idx
      while j < idx + win
        sum += mono[j] * mono[j]
        j += 1
      end
      levels << Math.sqrt(sum / win)
      idx += win
    end
    return [] if levels.length < 8

    peak = levels.max
    return [] unless peak.positive?

    floor = peak * ONSET_FLOOR_RATIO
    # A running average of the four windows before this one: twenty
    # milliseconds of "the recent past".
    found = []
    (4...levels.length).each do |i|
      recent = (levels[(i - 4)...i].sum / 4.0)
      next if levels[i] < floor
      next if levels[i] < recent * ONSET_LIFT

      found << (i * win).to_f / rate
    end
    found
  end

  # Turns onset times into slice boundaries, and drops the ones too close
  # together to be separate notes.
  def slice_points(mono, rate: RATE)
    points = onsets(mono, rate:)
    duration = mono.length.to_f / rate
    points = [0.0] if points.empty?
    points.unshift(0.0) unless points.first < MIN_SLICE_SEC

    kept = []
    points.each do |t|
      next if kept.any? && (t - kept.last) < MIN_SLICE_SEC

      kept << t
    end
    kept << duration

    # Pair each boundary with the next to make spans, then discard the ones too
    # long to be a piece of a phrase.
    spans = kept.each_cons(2).filter_map do |a, b|
      len = b - a
      next if len < MIN_SLICE_SEC

      [a, [len, MAX_SLICE_SEC].min]
    end
    return spans if spans.length <= MAX_SLICES

    # Too many: keep the loudest, which are the ones with a clear attack.
    spans.max_by(MAX_SLICES) { |(start, len)| span_energy(mono, start, len, rate) }
         .sort_by(&:first)
  end

  def span_energy(mono, start, len, rate)
    from = (start * rate).to_i
    to = [((start + len) * rate).to_i, mono.length].min
    return 0.0 if to <= from

    sum = 0.0
    i = from
    while i < to
      sum += mono[i] * mono[i]
      i += 1
    end
    Math.sqrt(sum / (to - from))
  end

  # ----------------------------------------------------------------- listening

  # Which of the twelve notes does this piece sound like?
  #
  # For each of the twelve, we measure how much energy the piece holds at that
  # note across five octaves, and pick the strongest. The measurement is a
  # Goertzel filter, which answers "how much of exactly this frequency is
  # present" more cheaply than a full spectrum when you only care about sixty
  # frequencies.
  CHROMA_OCTAVES = (2..6).freeze
  A4_HZ = 440.0

  def dominant_pitch_class(mono, start, len, rate: RATE)
    from = (start * rate).to_i
    to = [((start + len) * rate).to_i, mono.length].min
    return nil if to - from < 512

    window = mono[from...to]
    strength = Array.new(12, 0.0)
    12.times do |pc|
      CHROMA_OCTAVES.each do |octave|
        # MIDI note number for this pitch class in this octave, then its
        # frequency by the usual equal-temperament formula.
        midi = (octave * 12) + pc + 12
        hz = A4_HZ * (2.0**((midi - 69) / 12.0))
        next if hz > rate / 2.5

        strength[pc] += goertzel(window, hz, rate)
      end
    end
    best = strength.each_with_index.max_by(&:first)
    return nil unless best&.first&.positive?

    best.last
  end

  # How much of one frequency is in this signal. The standard Goertzel
  # recurrence: cheaper than an FFT when the frequencies wanted are known.
  def goertzel(window, hz, rate)
    coeff = 2.0 * Math.cos(2.0 * Math::PI * hz / rate)
    s1 = 0.0
    s2 = 0.0
    window.each do |sample|
      s0 = sample + (coeff * s1) - s2
      s2 = s1
      s1 = s0
    end
    Math.sqrt([(s1 * s1) + (s2 * s2) - (coeff * s1 * s2), 0.0].max) / window.length
  end

  def analyse(mono, spans, rate: RATE)
    spans.each_with_index.map do |(start, len), i|
      {
        index: i, start:, length: len,
        pitch_class: dominant_pitch_class(mono, start, len, rate:),
        energy: span_energy(mono, start, len, rate),
      }
    end.select { |s| s[:pitch_class] }
  end

  # ----------------------------------------------------------------- arranging

  # Where in the bar the pieces land.
  #
  # Not every sixteenth: a line that plays on all sixteen is a texture, not a
  # line. These are sparse, syncopated figures -- notes on the offbeats, gaps
  # where the ear expects a note. Each is sixteen slots; true means play.
  #
  # They are written out rather than generated because rhythm is the one thing
  # random numbers are reliably bad at.
  # Three or four notes a bar, not six.
  #
  # The first version of these ran to six and seven hits, and the result was
  # busy in a way that is the opposite of the intent -- a line playing on most
  # of the sixteenths leaves the drums no room and gives the ear nothing to
  # anticipate. What makes a sampled figure sit is the silence around it: the
  # bar has sixteen places a note could go and only three of them are used, so
  # each one lands.
  #
  # Written out rather than generated, because rhythm is the one thing random
  # numbers are reliably bad at.
  FIGURES = [
    [0, 6, 11],           # the common one: downbeat, then pushing late
    [0, 3, 8],            # a quick pair, then the halfway mark
    [0, 8],               # two notes in a bar; lets the drums carry it
    [0, 6, 8, 14],        # the busiest here, and still only four
    [3, 8, 11],           # no downbeat -- floats over the bar line
    [0, 7, 10],           # answers itself across the halves
  ].freeze

  # How often a repetition of the phrase drops out entirely.
  #
  # Even three notes a bar becomes wallpaper if it never stops. A phrase that
  # goes missing for two bars and comes back is heard again on its return;
  # one that plays for sixteen bars straight is heard once, at the start.
  REST_CHANCE = 0.22

  # How often a late-bar note is played backwards. Roughly one bar in three has
  # one; more than that and the trick stops being a gesture and becomes the
  # texture of the track.
  REVERSE_CHANCE = 0.30

  # How often a downbeat or halfway slot takes a voice instead of an instrument.
  # Two in five of the eligible slots, and only two slots a bar are eligible, so
  # a voice appears roughly once a bar at most.
  VOCAL_CHANCE = 0.40

  # A phrase is two bars long. Long enough to say something, short enough that
  # the ear has heard it twice before the section turns over.
  MOTIF_BARS = 2

  # How far the line may roam above and below where it started, counted in
  # chord tones. Seven degrees is a little over an octave once the degrees are
  # wrapped onto a three- or four-note chord -- enough range to have a shape,
  # tight enough to stay one voice rather than wandering off.
  DEGREE_FLOOR = -2
  DEGREE_CEILING = 4

  # Composes the phrase.
  #
  # The phrase is stored as a SHAPE rather than as notes: each slot carries a
  # degree, meaning "the third note of whatever chord is playing", not "an E".
  # The same shape can then be played over every chord in the progression and
  # will be in tune with each -- which is how a melody stays recognisable while
  # the harmony moves underneath it.
  #
  # The shape moves mostly by one degree at a time. Melodies are overwhelmingly
  # stepwise; leaps are rare and are what a listener remembers. One in four
  # here, and a leap is followed by a pull back toward the middle, because a
  # line that leaps twice in the same direction stops sounding like a line.
  def build_motif(rng)
    figure = FIGURES[rng.rand(FIGURES.length)]
    degree = rng.rand(3)
    MOTIF_BARS.times.flat_map do |bar|
      # The second bar answers the first rather than repeating it. Using one
      # figure for both made a two-bar phrase that was a one-bar phrase
      # played twice, which is the flat, circular quality the motif was meant to
      # cure. The answer holds back the last note and pushes into the bar line
      # instead -- call, then response.
      slots = bar.zero? ? figure : answer(figure)
      slots.map do |step|
        here = degree
        leap = rng.rand < 0.25
        move = leap ? [2, 3, -2, -3][rng.rand(4)] : [1, -1][rng.rand(2)]
        # Turn around at the edges of the range rather than stopping at them.
        #
        # Clamping looks like the same thing and is not: a line that keeps
        # rising against a ceiling produces the SAME degree over and over, and
        # three identical notes in a row is exactly the flatness the motif is
        # here to cure. One phrase came out ending "4 4 4". Reflecting sends the
        # line back down instead, which is also what a melody does when it
        # reaches its top note.
        move = -move if (degree + move) > DEGREE_CEILING || (degree + move) < DEGREE_FLOOR
        degree = (degree + move).clamp(DEGREE_FLOOR, DEGREE_CEILING)
        # The downbeat is the accent. Everything else sits under it, which is
        # what makes a bar feel like a bar rather than a row of equal notes.
        { bar:, step:, degree: here, accent: step.zero? ? 1.0 : 0.82 }
      end
    end
  end

  # The response to a call: the same figure with its last note dropped and a
  # note added on the final sixteenth, which leans into the next bar's downbeat.
  # A phrase that ends early and then pushes is a phrase that wants continuing.
  def answer(figure)
    dropped = figure.last
    kept = figure[0...-1]
    # A pickup that is neither already in the call nor the very note just
    # dropped. Both exclusions were learned the same way, twice: a fixed
    # sixteenth changed nothing when the figure already ended on it, and then
    # choosing "any slot not in the remainder" happily chose back the note that
    # had been removed. Either way the response came out identical to the
    # call and the call-and-response was a no-op that reads correctly in the
    # source. Hence the guarantee below rather than trust.
    pickup = [14, 13, 15, 11, 10].find { |p| !kept.include?(p) && p != dropped }
    result = (kept + [pickup].compact).sort
    result == figure ? kept : result
  end

  # Lays the phrase out across the whole track.
  #
  # Every repetition is the same shape over a possibly different chord. The
  # fourth repetition is varied -- the tail of the phrase is re-drawn -- so the
  # section turns over instead of running on unchanged. That is the oldest trick
  # in popular music: three the same, the fourth different.
  def arrange(slices, chord_tones, bars:, seed:)
    return [] if slices.empty?

    rng = Random.new(seed)
    # Reversal and voice each draw from their own stream. Sharing one meant that
    # adding the reverse decision consumed numbers the rest-and-pick logic was
    # using, and every other choice in the arrangement shifted -- the note count
    # halved from a change that was supposed to affect nothing but direction. A
    # decision that alters unrelated decisions is not a knob, it is a hazard.
    flip_rng = Random.new(seed ^ 0x7e7e)
    vocal_rng = Random.new(seed ^ 0x3131)
    vocals = slices.select { |s| s[:vocal] }
    instruments = slices.reject { |s| s[:vocal] }
    instruments = slices if instruments.empty?
    motif = build_motif(rng)
    variant = build_motif(rng)
    events = []
    previous = nil

    (0...bars).step(MOTIF_BARS).each_with_index do |bar0, repetition|
      # Sit one out now and then -- but never the first, which is where the
      # listener learns the phrase.
      next if repetition.positive? && rng.rand < REST_CHANCE

      phrase = ((repetition % 4) == 3) ? variant : motif
      phrase.each do |note|
        bar = bar0 + note[:bar]
        next if bar >= bars

        tones = chord_tones[bar % chord_tones.length]
        next if tones.nil? || tones.empty?

        # The degree, wrapped into the chord actually playing. A shape asking
        # for its fifth note over a three-note chord gets the second one.
        # A voice, or an instrument?
        #
        # Vocal fragments are punctuation, not melody. They land on the downbeat
        # and the halfway mark -- where a word would fall if someone were talking
        # over the beat -- and never often enough to become the tune. Donuts uses
        # them this way throughout: a syllable, often too short to make out, as
        # rhythm rather than as singing.
        want_vocal = vocals.any? && [0, 8].include?(note[:step]) && vocal_rng.rand < VOCAL_CHANCE
        pool = want_vocal ? vocals : instruments
        pick = best_slice(pool, target = tones[note[:degree] % tones.length], previous, rng)
        # A voice that cannot reach the note within two semitones is better left
        # out than dragged there, so fall back to the instruments rather than
        # widening the retune.
        pick ||= best_slice(instruments, target, previous, rng) if want_vocal
        next unless pick

        # A reversed piece is an event, not a texture. On the downbeat it would
        # swallow the accent the phrase is built around, so it is only ever
        # allowed on the last note of a bar -- where its swell leads into the
        # next downbeat instead of covering one.
        reverse = note[:step] >= 10 && flip_rng.rand < REVERSE_CHANCE
        events << { bar:, step: note[:step], slice: pick[:slice], reverse:,
                    vocal: pick[:slice][:vocal],
                    shift: pick[:shift], gain: note[:accent], degree: note[:degree] }
        previous = pick[:slice][:index]
      end
    end
    events
  end

  # How far a VOICE may be retuned.
  #
  # Much less than an instrument. A trumpet moved four semitones by varispeed is
  # a trumpet in a different key; a voice moved four semitones is a different
  # person, and usually a comic one. Two is the limit before the ear starts
  # hearing the machine instead of the singer.
  MAX_VOCAL_SHIFT = 2

  # The piece nearest the wanted note, counting a retune as a cost.
  def best_slice(slices, target_pc, previous_index, rng)
    scored = slices.filter_map do |slice|
      shift = semitone_distance(slice[:pitch_class], target_pc)
      limit = slice[:vocal] ? MAX_VOCAL_SHIFT : MAX_SHIFT_SEMITONES
      next if shift.abs > limit

      cost = shift.abs.to_f
      cost += 3.0 if slice[:index] == previous_index
      # A whisper of noise so two equally good pieces do not always resolve the
      # same way, which would make the figure mechanical.
      cost += rng.rand * 0.4
      { slice:, shift:, cost: }
    end
    scored.min_by { |s| s[:cost] }
  end

  # The shortest way round the twelve notes: from B to C is one step up, not
  # eleven down.
  def semitone_distance(from_pc, to_pc)
    diff = (to_pc - from_pc) % 12
    diff > 6 ? diff - 12 : diff
  end

  # ------------------------------------------------------------------- playing

  # Lays the chosen pieces onto the beat.
  #
  # Two details do most of the work here. The pieces are retuned by playing
  # them faster or slower, which is what a sampler does and why a retuned
  # sample sounds like a sampler rather than like a pitch-shifter. And each one
  # lands a few milliseconds off its slot, because a person playing pads lands
  # a few milliseconds off, and that lateness is the whole feel.
  # One note at a time, and each one makes way for the next.
  #
  # Pieces are not laid down at their full length and left to overlap, which
  # sounds three unrelated fragments of a record at once. That is where
  # mud comes from, and no amount of mixing repairs it -- the parts genuinely
  # are all playing. A sampler pad does not behave that way: hitting the next
  # pad stops the last. So a note now runs until the next note begins, plus a
  # short tail for it to decay into, and the two overlap only across that tail.
  #
  # The tail is thirty-five milliseconds, long enough that consecutive pieces
  # bleed into one another rather than butt together.
  RELEASE_SEC = 0.035

  def render(mono_l, mono_r, events, bpm:, bars:, seed:)
    beat = 60.0 / bpm
    step_sec = beat / 4.0
    total = (bars * 4 * beat * RATE).ceil + RATE
    left = Array.new(total, 0.0)
    right = Array.new(total, 0.0)
    rng = Random.new(seed ^ 0x5f5f)

    # Absolute times first, in order, so each note knows when the next arrives.
    timed = events.map do |event|
      # Late, and more so on the offbeats -- the drag that makes a figure sit
      # behind the beat instead of on it.
      drag = (event[:step].odd? ? 0.011 : 0.004) + (rng.rand * 0.006)
      at = (event[:bar] * 4 * beat) + (event[:step] * step_sec) + drag
      event.merge(at:)
    end.sort_by { |e| e[:at] }

    timed.each_with_index do |event, i|
      frame = (event[:at] * RATE).to_i
      next if frame >= total

      following = timed[i + 1]
      room = following ? (following[:at] - event[:at]) + RELEASE_SEC : event[:slice][:length]
      # Each piece carries its own source, since the pool may be drawn from more
      # than one record.
      src = event[:slice][:source] || { left: mono_l, right: mono_r }
      place(left, right, src[:left], src[:right], event[:slice], frame,
            2.0**(event[:shift] / 12.0), room, event[:gain] || 1.0,
            reverse: event[:reverse])
    end
    [left, right]
  end

  # Copies one piece into the output: resampled for pitch, optionally played
  # backwards, cut to the room it has, and faded at both ends.
  #
  # Playing a piece backwards is the oldest sampler trick there is and it does
  # something nothing else does: a note's decay becomes its attack, so a piano
  # chord arrives as a swell that stops dead on the beat. It is unmistakably a
  # sample being played, which is the sound this whole engine is after, and it
  # costs one sign change in the read position.
  def place(left, right, src_l, src_r, slice, at, ratio, room, gain, reverse: false)
    available = (slice[:length] / ratio * RATE).to_i
    out_frames = [available, (room * RATE).to_i].min
    return if out_frames < 2

    # Forwards, start at the beginning and walk up. Backwards, start at the end
    # of the piece and walk down.
    start_frame = (slice[:start] * RATE).to_i
    from = reverse ? start_frame + (slice[:length] * RATE).to_i : start_frame
    step = reverse ? -ratio : ratio

    attack = (EDGE_FADE_SEC * RATE).to_i
    release = (RELEASE_SEC * RATE).to_i
    i = 0
    while i < out_frames
      dest = at + i
      break if dest >= left.length

      # Where in the original this output sample comes from. A fractional
      # position between two samples, mixed in proportion -- linear
      # interpolation, which is what makes the retune smooth rather than gritty.
      pos = from + (i * step)
      base = pos.to_i
      break if base < 0 || base + 1 >= src_l.length

      frac = pos - base
      envelope = edge_gain(i, out_frames, attack, release) * gain
      left[dest] += ((src_l[base] * (1 - frac)) + (src_l[base + 1] * frac)) * envelope
      right[dest] += ((src_r[base] * (1 - frac)) + (src_r[base + 1] * frac)) * envelope
      i += 1
    end
  end

  # A fast fade in and a slow fade out. The fade out is a curve rather than a
  # straight line -- squared, so it falls away quickly at first and then trails,
  # which is how a struck note decays and a linear ramp is not.
  def edge_gain(i, total, attack, release)
    gain = 1.0
    gain *= i.to_f / attack if attack.positive? && i < attack
    if release.positive? && i > total - release
      remaining = [(total - i).to_f / release, 0.0].max
      gain *= remaining * remaining
    end
    gain
  end

  # ---------------------------------------------------------------- assembling

  # Keeps the result from clipping without flattening it. Peak normalisation to
  # a hair under full scale: the master chain does the real levelling later, and
  # arriving there already squashed would leave it nothing to work with.
  def normalise!(left, right, ceiling: 0.89)
    peak = 0.0
    left.each { |v| peak = v.abs if v.abs > peak }
    right.each { |v| peak = v.abs if v.abs > peak }
    return if peak.zero? || peak <= ceiling

    scale = ceiling / peak
    left.map! { |v| v * scale }
    right.map! { |v| v * scale }
  end

  # The whole job, start to finish.
  #
  # `chord_tones` is one entry per chord of the progression, each a list of the
  # twelve-note classes in that chord. Returns the path written, plus a short
  # description of what it did, or nil when the record yielded too few usable
  # pieces to play anything -- in which case the caller falls back to looping,
  # which is worse but is not silence.
  # `loop_path` may be one record or several.
  #
  # A track built from a single record can only ever say one thing. Donuts moves
  # between sources inside ninety seconds, and the reason it works is that the
  # arranging step does not care where a piece came from -- it asks only what
  # pitch the piece is, so pieces from two different records sort themselves
  # into one line by pitch alone. A horn from one record answers a piano from
  # another because they are a third apart, not because anyone planned it.
  def build!(loop_path:, dest:, bpm:, bars:, chord_tones:, seed: 4242, vocal_path: nil)
    sources = Array(loop_path).uniq
    return nil if sources.empty?

    pool = []
    primary = nil
    # Instrument records first, then any vocal stems. The tag is all that
    # separates them downstream: the cutting and pitch-finding are identical,
    # because a voice is another thing with a pitch and an attack.
    tagged = sources.map { |p| [p, false] } + Array(vocal_path).uniq.map { |p| [p, true] }
    tagged.each do |path, vocal|
      next unless path && File.file?(path)

      left, right = decode(path)
      next if left.length < RATE / 2

      primary ||= [left, right] unless vocal
      mono = Array.new(left.length) { |i| (left[i] + right[i]) * 0.5 }
      found = analyse(mono, slice_points(mono))
      # Each piece remembers the audio it was cut from, so the playback stage
      # can read the right record without keeping them in step.
      found.each { |s| s[:source] = { left:, right: }; s[:vocal] = vocal }
      pool.concat(found)
    end
    return nil if primary.nil? || pool.length < MIN_SLICES

    # Re-number after pooling: `index` is what stops a piece following itself,
    # and two records each numbering from zero would make unrelated pieces look
    # like the same piece.
    pool.each_with_index { |s, i| s[:index] = i }

    events = arrange(pool, chord_tones, bars:, seed:)
    return nil if events.empty?

    out_l, out_r = render(primary[0], primary[1], events, bpm:, bars:, seed:)
    normalise!(out_l, out_r)
    encode!(out_l, out_r, dest)
    { path: dest, slices: pool.length, events: events.length, records: sources.length,
      reversed: events.count { |e| e[:reverse] },
      vocal_slices: pool.count { |s| s[:vocal] }, vocal_events: events.count { |e| e[:vocal] },
      pitches: pool.map { |s| s[:pitch_class] } }
  end
end
