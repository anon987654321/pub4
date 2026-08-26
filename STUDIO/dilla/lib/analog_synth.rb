# frozen_string_literal: true

require "fileutils"

# An analogue synthesiser, built rather than borrowed.
#
# Every synthetic sound in this engine has until now come from FluidSynth
# playing a General MIDI soundfont: you ask for program 89 and you get whatever
# somebody sampled into that slot years ago. It is convenient and it is a hard
# ceiling. You cannot open the filter, because there is no filter. You cannot
# detune the second oscillator, because there is no second oscillator. There is
# only a recording of a sound somebody else made, and the most you can do is
# equalise it afterwards.
#
# This is the other way: oscillators, a filter, envelopes, and the arithmetic
# between them. It is the design every analogue synthesiser from the sixties
# onward shares, and it is about two hundred lines.
#
#   OSCILLATORS   make a raw, bright, harmonically rich waveform.
#   FILTER        removes the harmonics you do not want. This is where nearly
#                 all the character lives.
#   ENVELOPES     decide how loudness and brightness change over the life of a
#                 note -- the difference between a struck piano and a bowed
#                 string, played on identical oscillators.
#
# Two details separate a synthesiser that sounds analogue from one that sounds
# like a calculator, and both are imperfections:
#
#   DETUNE. Real oscillators drift. Two sawtooths a few cents apart beat against
#   each other, slowly, and the ear hears that beating as size. Perfectly tuned
#   oscillators sum to something thinner than either one alone.
#
#   DRIFT. Real circuits wander with temperature and age. A note played twice is
#   never quite the same note. A fixed random offset per voice is enough to stop
#   a chord sounding printed.
module AnalogSynth
  RATE = 44_100

  # The wave shapes, and what each is for.
  #
  # SAW has every harmonic, falling away gently. It is the brightest and the
  # most useful: strings, brass, and almost every bass ever programmed.
  # SQUARE has only the odd harmonics, which makes it hollow -- a clarinet
  # rather than a violin. Woody, and the classic reggae bass.
  # TRIANGLE has odd harmonics too, but they fall away fast, so it is nearly a
  # sine with a little edge. Flutes and soft sub-bass.
  # SINE has no harmonics at all. Only a fundamental. Sub-bass, and the bottom
  # octave of anything that needs weight without mud.
  module_function

  # ------------------------------------------------------------- oscillators

  # One sample of a waveform at a given point in its cycle.
  #
  # `phase` runs 0 to 1 across one cycle. Everything below is that cycle drawn
  # as arithmetic rather than looked up in a table, which costs a little speed
  # and buys exactness.
  def wave(shape, phase)
    case shape
    when :saw then (2.0 * phase) - 1.0
    when :square then phase < 0.5 ? 1.0 : -1.0
    when :triangle then phase < 0.5 ? (4.0 * phase) - 1.0 : 3.0 - (4.0 * phase)
    else Math.sin(2.0 * Math::PI * phase)
    end
  end

  # ------------------------------------------------------------------ filter
  #
  # A four-pole resonant low-pass -- the Moog ladder, near enough.
  #
  # Four one-pole filters in series, each removing a little more of the top.
  # Four of them gives 24 dB per octave, which is the steep, definite sound of a
  # Moog; two would give 12, which is the gentler Oberheim and Roland character.
  #
  # Resonance is feedback: some of the output is subtracted from the input, and
  # because the filter has delayed it, the subtraction cancels at most
  # frequencies but REINFORCES at the cutoff. That peak is the whole reason
  # anyone cares about filters. Turn it up far enough and the filter oscillates
  # on its own with no input at all.
  #
  # State lives in the four `z` values, which is why this is a class rather than
  # a function -- a filter is a thing with a memory.
  class Ladder
    def initialize(rate: RATE)
      @rate = rate
      @z = [0.0, 0.0, 0.0, 0.0]
    end

    # `cutoff` in hertz, `resonance` from 0 to about 1.1. Above 1 it self
    # oscillates, which is a sound in itself and also a way to lose a mix.
    #
    # A straight cascade: each stage moves a little way toward the one before
    # it, and the last stage feeds back into the input. Both parts matter and
    # the first version got the second one wrong -- it averaged each stage with
    # its own previous value, which is an extra smoothing step that shifts the
    # phase of the feedback and cancels the resonance entirely. Measured across
    # resonance 0.1 to 0.9 it moved the level at cutoff by half a decibel: the
    # knob was connected to nothing.
    def process(sample, cutoff, resonance)
      # Two corrections, both of which the first version got wrong, and together
      # they put the cutoff an octave and a half below where it was asked for --
      # a filter set to 800 Hz whose real corner was near 150.
      #
      # First, the coefficient for a one-pole lowpass is 1 - e^(-2*pi*fc/rate),
      # not 2*fc/rate. The second is the small-angle approximation of the first
      # and is 2.6 times too small at these frequencies.
      #
      # Second, where should "cutoff" point?
      #
      # Two answers, and the textbook one is wrong here. Four one-poles in
      # series reach -3 dB well below where any single stage does, by a factor
      # of about 0.435, so correcting for that puts the composite -3 dB point
      # exactly at the number asked for. That was tried. It also moves the
      # RESONANT PEAK up to the pole frequency, 2.3 times higher -- a filter set
      # to 800 Hz that whistled at 1700.
      #
      # On a real ladder the cutoff control marks the pole, which is where the
      # thing peaks and where a player hears it. With resonance down the
      # composite is already a few decibels off at that mark, and no one minds,
      # because nobody plays a resonant filter by its -3 dB point. So the stage
      # frequency IS the cutoff, and the correction stays here only as the
      # explanation for why it is not used.
      stage_hz = cutoff.clamp(20.0, @rate * 0.45)
      f = 1.0 - Math.exp(-2.0 * Math::PI * stage_hz / @rate)
      fb = resonance * 4.0

      # Feedback from the last stage. This is the entire resonance: the delayed
      # output subtracted from the input cancels at most frequencies but adds at
      # the cutoff, because that is where the four stages have turned it around.
      input = sample - (fb * @z[3])
      input = soft(input)

      @z[0] += f * (input - @z[0])
      @z[1] += f * (@z[0] - @z[1])
      @z[2] += f * (@z[1] - @z[2])
      @z[3] += f * (@z[2] - @z[3])
      @z[3]
    end

    # The transistors in a real ladder saturate, which is why a Moog gets fatter
    # rather than louder as it is driven, and why the resonance never quite
    # tears. tanh is the standard stand-in for that curve.
    def soft(x) = Math.tanh(x)
  end

  # --------------------------------------------------------------- envelopes
  #
  # Attack, decay, sustain, release -- the four numbers behind every synthesised
  # sound since 1965. Attack is how long it takes to reach full; decay how long
  # to fall from there to the sustain level; sustain the level it holds while a
  # key is down; release how long it takes to fall silent after the key is up.
  #
  # A struck sound (piano, plucked string) has no attack to speak of and no
  # sustain. A bowed or blown sound has a slow attack and a high sustain. The
  # oscillators can be identical.
  Envelope = Struct.new(:attack, :decay, :sustain, :release, keyword_init: true) do
    # Level at `t` seconds into a note that is held for `held` seconds.
    def at(t, held)
      return 0.0 if t.negative?

      if t < attack
        attack.zero? ? 1.0 : t / attack
      elsif t < attack + decay
        decay.zero? ? sustain : 1.0 - ((1.0 - sustain) * ((t - attack) / decay))
      elsif t < held
        sustain
      else
        gone = t - held
        return 0.0 if release <= 0 || gone >= release

        # Squared, so it falls quickly and then trails. A straight line sounds
        # like someone turning a knob down.
        remaining = 1.0 - (gone / release)
        sustain * remaining * remaining
      end
    end

    def total(held) = held + release
  end

  # ------------------------------------------------------------------ patches
  #
  # Each is one instrument. The comments say what the settings are FOR, because
  # a list of numbers explains nothing.
  PATCHES = {
    # Three saws, well detuned, into a filter that shuts fast. The classic
    # Minimoog bass: the envelope closes the filter within a fifth of a second,
    # so every note begins bright and immediately darkens -- which the ear reads
    # as a plucked attack even though nothing was plucked.
    moog_bass: {
      waves: %i[saw saw saw], detune: [0.0, -7.0, 5.0], octaves: [0, 0, -1],
      cutoff: 220.0, env_amount: 2400.0, resonance: 0.62, drive: 1.25,
      amp: Envelope.new(attack: 0.004, decay: 0.30, sustain: 0.55, release: 0.20),
      filter_env: Envelope.new(attack: 0.002, decay: 0.18, sustain: 0.12, release: 0.15),
    },
    # Two saws barely apart, a filter left open, a slow swell. Strings.
    poly_strings: {
      waves: %i[saw saw], detune: [-4.0, 6.0], octaves: [0, 0],
      cutoff: 1500.0, env_amount: 1800.0, resonance: 0.22, drive: 1.0,
      amp: Envelope.new(attack: 0.28, decay: 0.6, sustain: 0.78, release: 0.9),
      filter_env: Envelope.new(attack: 0.55, decay: 1.2, sustain: 0.55, release: 0.8),
    },
    # Square waves are hollow, and hollow is what a Rhodes-ish electric key
    # sounds like once the bell has faded. Fast attack, long decay, no sustain:
    # struck, not held.
    e_piano: {
      waves: %i[triangle square], detune: [0.0, 3.0], octaves: [0, 1],
      cutoff: 900.0, env_amount: 2600.0, resonance: 0.18, drive: 1.1,
      amp: Envelope.new(attack: 0.003, decay: 1.4, sustain: 0.0, release: 0.5),
      filter_env: Envelope.new(attack: 0.001, decay: 0.5, sustain: 0.1, release: 0.4),
    },
    # One saw, one square an octave down, resonance high enough to whistle, and
    # a filter envelope that slams. This is the acid sound, and the resonance is
    # doing all of the work.
    acid: {
      waves: %i[saw square], detune: [0.0, 0.0], octaves: [0, -1],
      cutoff: 180.0, env_amount: 3200.0, resonance: 0.92, drive: 1.6,
      amp: Envelope.new(attack: 0.002, decay: 0.24, sustain: 0.25, release: 0.10),
      filter_env: Envelope.new(attack: 0.001, decay: 0.22, sustain: 0.05, release: 0.10),
    },
    # A sine and a triangle, nothing else, filter almost shut. Weight with no
    # mud -- the note is felt rather than heard, which is what a sub is for.
    sub: {
      waves: %i[sine triangle], detune: [0.0, 0.0], octaves: [-1, -1],
      cutoff: 220.0, env_amount: 200.0, resonance: 0.1, drive: 1.0,
      amp: Envelope.new(attack: 0.01, decay: 0.4, sustain: 0.7, release: 0.25),
      filter_env: Envelope.new(attack: 0.01, decay: 0.3, sustain: 0.4, release: 0.2),
    },
    # Slow, wide, and dark: the pad. Two saws and a square, all detuned, filter
    # opening over a second and a half so the chord arrives rather than starts.
    warm_pad: {
      waves: %i[saw saw square], detune: [-8.0, 9.0, 0.0], octaves: [0, 0, -1],
      cutoff: 700.0, env_amount: 1400.0, resonance: 0.3, drive: 1.05,
      amp: Envelope.new(attack: 0.35, decay: 1.0, sustain: 0.8, release: 1.2),
      filter_env: Envelope.new(attack: 1.5, decay: 1.5, sustain: 0.6, release: 1.0),
    },
  }.freeze

  # -------------------------------------------------------------- the engine

  # Renders one note into a pair of channel buffers.
  #
  # `hz` is the pitch, `at` the time it starts, `held` how long the key is down.
  # Voices are rendered one at a time and summed, which is exactly what a
  # polyphonic synthesiser does.
  def render_note!(left, right, patch:, hz:, at:, held:, gain: 1.0, seed: 0)
    spec = PATCHES.fetch(patch) { PATCHES.fetch(:warm_pad) }
    rng = Random.new(seed)
    # Analogue drift: this voice is a few cents off, permanently, and its
    # oscillators do not start at the same point in their cycles. Both are
    # imperfections and both are why it does not sound printed.
    voice_drift = 2.0**((rng.rand(-4.0..4.0)) / 1200.0)
    phases = spec[:waves].map { rng.rand }

    ladder = Ladder.new
    start = (at * RATE).to_i
    frames = (spec[:amp].total(held) * RATE).to_i
    return if frames < 2 || start >= left.length

    # Precompute the frequency of each oscillator once rather than per sample.
    freqs = spec[:waves].each_index.map do |i|
      hz * voice_drift * (2.0**spec[:octaves][i]) * (2.0**(spec[:detune][i] / 1200.0))
    end
    level = 1.0 / spec[:waves].length

    i = 0
    while i < frames
      dest = start + i
      break if dest >= left.length

      t = i.to_f / RATE
      # Oscillators, summed.
      raw = 0.0
      spec[:waves].each_with_index do |shape, k|
        phases[k] = (phases[k] + (freqs[k] / RATE)) % 1.0
        raw += wave(shape, phases[k]) * level
      end

      # The filter envelope decides the cutoff, moment by moment. This is the
      # single most important line here: a static filter is a tone control, and
      # a moving one is an instrument.
      cutoff = spec[:cutoff] + (spec[:env_amount] * spec[:filter_env].at(t, held))
      filtered = ladder.process(raw * spec[:drive], cutoff.clamp(30.0, 18_000.0), spec[:resonance])

      amp = spec[:amp].at(t, held) * gain
      # A hair of stereo, from the drift rather than from a widener: the two
      # channels are the same voice at slightly different levels, which is
      # what two channels of an analogue desk actually were.
      left[dest] += filtered * amp * 0.52
      right[dest] += filtered * amp * 0.48
      i += 1
    end
  end

  # Renders a list of notes to a file.
  #
  # Each note is {hz:, at:, held:, gain:}. Returns the path, or nil if there was
  # nothing to play.
  def render!(notes, dest:, patch:, duration:, seed: 4242)
    return nil if notes.empty?

    frames = (duration * RATE).ceil + RATE
    left = Array.new(frames, 0.0)
    right = Array.new(frames, 0.0)

    notes.each_with_index do |note, i|
      render_note!(left, right, patch:, hz: note[:hz], at: note[:at],
                   held: note[:held], gain: note[:gain] || 1.0, seed: seed + i)
    end

    peak = 0.0
    left.each { |v| peak = v.abs if v.abs > peak }
    right.each { |v| peak = v.abs if v.abs > peak }
    return nil if peak.zero?

    # Leave headroom. The master chain does the levelling, and arriving there
    # already at full scale gives it nothing to work with.
    scale = 0.82 / peak
    left.map! { |v| v * scale }
    right.map! { |v| v * scale }
    write!(left, right, dest)
  end

  def write!(left, right, dest)
    FileUtils.mkdir_p(File.dirname(dest))
    inter = Array.new(left.length * 2)
    i = 0
    while i < left.length
      inter[i * 2] = (left[i] * 32_767.0).round.clamp(-32_768, 32_767)
      inter[(i * 2) + 1] = (right[i] * 32_767.0).round.clamp(-32_768, 32_767)
      i += 1
    end
    IO.popen(["ffmpeg", "-y", "-v", "quiet", "-f", "s16le", "-ar", RATE.to_s,
              "-ac", "2", "-i", "-", "-c:a", "pcm_s16le", dest], "wb") do |io|
      io.write(inter.pack("s<*"))
    end
    dest
  end
end
