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
    return nil unless best && best.first.positive?

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
  FIGURES = [
    [0, 3, 6, 8, 11, 14],       # the common one: on the one, then pushing
    [0, 2, 5, 8, 10, 13],       # earlier in the second half
    [0, 6, 8, 14],              # sparse, lets the drums carry it
    [0, 3, 4, 8, 11, 12, 14],   # busier, doubles on 3-4 and 11-12
    [2, 5, 8, 11, 14],          # starts late, no downbeat -- floats
    [0, 4, 7, 8, 12, 15],       # answers itself across the halves
  ].freeze

  # Picks a piece for every slot of the arrangement.
  #
  # The rule: whatever chord is playing underneath, choose the piece whose own
  # pitch is nearest one of that chord's notes, and retune it the rest of the
  # way. So the flip PLAYS the progression rather than sitting on top of it.
  #
  # A piece is penalised for following itself. Repetition is what a loop does;
  # avoiding it is most of what makes this sound played.
  def arrange(slices, chord_tones, bars:, seed:)
    return [] if slices.empty?

    rng = Random.new(seed)
    figure = FIGURES[rng.rand(FIGURES.length)]
    events = []
    previous = nil

    bars.times do |bar|
      tones = chord_tones[bar % chord_tones.length]
      next if tones.nil? || tones.empty?

      # A different figure every fourth bar, so the phrase turns over.
      active = ((bar % 4) == 3) ? FIGURES[(FIGURES.index(figure) + 1) % FIGURES.length] : figure
      active.each do |step|
        target = tones[rng.rand(tones.length)]
        pick = best_slice(slices, target, previous, rng)
        next unless pick

        events << { bar:, step:, slice: pick[:slice], shift: pick[:shift] }
        previous = pick[:slice][:index]
      end
    end
    events
  end

  # The piece nearest the wanted note, counting a retune as a cost.
  def best_slice(slices, target_pc, previous_index, rng)
    scored = slices.filter_map do |slice|
      shift = semitone_distance(slice[:pitch_class], target_pc)
      next if shift.abs > MAX_SHIFT_SEMITONES

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
  def render(mono_l, mono_r, events, bpm:, bars:, seed:)
    beat = 60.0 / bpm
    step_sec = beat / 4.0
    total = (bars * 4 * beat * RATE).ceil + RATE
    left = Array.new(total, 0.0)
    right = Array.new(total, 0.0)
    rng = Random.new(seed ^ 0x5f5f)

    events.each do |event|
      slice = event[:slice]
      ratio = 2.0**(event[:shift] / 12.0)
      # Late, and more so on the offbeats -- the drag that makes a figure sit
      # behind the beat instead of on it.
      drag = (event[:step].odd? ? 0.011 : 0.004) + (rng.rand * 0.006)
      at = (((event[:bar] * 4 * beat) + (event[:step] * step_sec) + drag) * RATE).to_i
      next if at >= total

      place(left, right, mono_l, mono_r, slice, at, ratio)
    end
    [left, right]
  end

  # Copies one piece into the output, resampled for pitch and faded at the ends.
  def place(left, right, src_l, src_r, slice, at, ratio)
    from = (slice[:start] * RATE).to_i
    frames = (slice[:length] * RATE).to_i
    out_frames = (frames / ratio).to_i
    return if out_frames < 2

    fade = (EDGE_FADE_SEC * RATE).to_i
    i = 0
    while i < out_frames
      dest = at + i
      break if dest >= left.length

      # Where in the original this output sample comes from. A fractional
      # position between two samples, mixed in proportion -- linear
      # interpolation, which is what makes the retune smooth rather than gritty.
      pos = from + (i * ratio)
      base = pos.to_i
      break if base + 1 >= src_l.length

      frac = pos - base
      gain = edge_gain(i, out_frames, fade)
      left[dest] += ((src_l[base] * (1 - frac)) + (src_l[base + 1] * frac)) * gain
      right[dest] += ((src_r[base] * (1 - frac)) + (src_r[base + 1] * frac)) * gain
      i += 1
    end
  end

  def edge_gain(i, total, fade)
    return 1.0 if fade < 1

    if i < fade
      i.to_f / fade
    elsif i > total - fade
      [(total - i).to_f / fade, 0.0].max
    else
      1.0
    end
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
  def build!(loop_path:, dest:, bpm:, bars:, chord_tones:, seed: 4242)
    left, right = decode(loop_path)
    return nil if left.length < RATE / 2

    mono = Array.new(left.length) { |i| (left[i] + right[i]) * 0.5 }
    spans = slice_points(mono)
    slices = analyse(mono, spans)
    return nil if slices.length < MIN_SLICES

    events = arrange(slices, chord_tones, bars:, seed:)
    return nil if events.empty?

    out_l, out_r = render(left, right, events, bpm:, bars:, seed:)
    normalise!(out_l, out_r)
    encode!(out_l, out_r, dest)
    { path: dest, slices: slices.length, events: events.length,
      pitches: slices.map { |s| s[:pitch_class] } }
  end
end
