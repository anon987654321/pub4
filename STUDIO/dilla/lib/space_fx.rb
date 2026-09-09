# frozen_string_literal: true

# Room and echo, computed rather than sampled.
#
# The engine's other effects are ffmpeg filter graphs, which is right for a
# render: ffmpeg is fast, it is already a dependency, and a graph can be printed
# and argued with. It is wrong for live playback, where the audio never becomes
# a file and there is nothing to hand ffmpeg. So this is the same two ideas
# written as arithmetic over a buffer.
#
# Both are the textbook constructions and neither is novel, which is the point:
# a reverb is a solved problem and an invented one sounds like a mistake.
module SpaceFx
  RATE = 44_100

  module_function

  # A chain, drawn rather than written down.
  #
  # The order matters more than the choice. Distortion before a filter sounds
  # like an instrument and after it sounds like a broken speaker; a room goes
  # last, because everything before it is the sound and the room is where the
  # sound happens. So the palette is drawn from freely and then SORTED into
  # that order, which is the difference between a chain and a pile.
  #
  # Reverb is always present and always last. Everything else is a coin toss,
  # and the coin is seeded, so a chain you liked can be played again.
  # Ordered by what each stage costs, cheapest first, because that is the order
  # a live chain has to be trimmed in. Every one of these is a per-sample Ruby
  # loop over both channels; the reverb is six passes of one and is on its own
  # about half of any chain it appears in.
  STAGE_COST = { tremolo: 1, fold: 1, crush: 1, chorus: 2, space_echo: 3, phaser: 4, reverb: 6 }.freeze

  STAGE_ORDER = %i[fold crush phaser chorus tremolo space_echo reverb].freeze

  # max_stages trims a drawn chain to fit a budget.
  #
  # Live has a deadline that a render does not: the samples must exist before
  # the speaker wants them, and a chain that misses it produces a gap, which is
  # worse than any effect it was going to add. Cheapest stages are dropped last
  # -- they buy the most character per millisecond -- and the reverb is kept
  # whatever else goes, because a dry line over a wet pad sounds like a mistake
  # rather than like a choice.
  def random_plan(rng, wet: 1.0, max_stages: nil)
    picked = {}
    picked[:fold] = { amount: rng.rand(1.4..2.6).round(2), mix: rng.rand(0.2..0.45).round(2) } if rng.rand < 0.35
    picked[:crush] = { bits: rng.rand(7..12), hold: rng.rand(1..4), mix: rng.rand(0.2..0.5).round(2) } if rng.rand < 0.3
    if rng.rand < 0.55
      picked[:phaser] = { rate_hz: rng.rand(0.12..0.9).round(3), depth: rng.rand(0.4..0.95).round(2),
                          stages: [4, 6, 8].sample(random: rng), feedback: rng.rand(0.2..0.6).round(2),
                          mix: rng.rand(0.3..0.6).round(2) }
    end
    if rng.rand < 0.7
      picked[:chorus] = { rate_hz: rng.rand(0.2..1.1).round(3), depth_ms: rng.rand(2.0..7.0).round(2),
                          mix: rng.rand(0.2..0.45).round(2) }
    end
    if rng.rand < 0.4
      picked[:tremolo] = { rate_hz: rng.rand(2.0..7.5).round(2), depth: rng.rand(0.2..0.6).round(2),
                           shape: rng.rand < 0.25 ? :square : :sine }
    end
    if rng.rand < 0.8
      picked[:space_echo] = { time: rng.rand(0.12..0.62).round(3), feedback: rng.rand(0.25..0.62).round(2),
                              mix: (rng.rand(0.2..0.45) * wet).round(2),
                              wow_hz: rng.rand(0.3..1.4).round(2), wow_ms: rng.rand(0.6..3.0).round(2) }
    end
    picked[:reverb] = { mix: (rng.rand(0.25..0.55) * wet).round(2), decay: rng.rand(0.72..0.9).round(2),
                        damping: rng.rand(0.2..0.5).round(2) }

    if max_stages && picked.length > max_stages
      # Sorted by cost descending, reverb exempt, and dropped until it fits.
      droppable = picked.keys.reject { |s| s == :reverb }
                        .sort_by { |s| -STAGE_COST.fetch(s, 2) }
      droppable.first(picked.length - max_stages).each { |s| picked.delete(s) }
    end

    STAGE_ORDER.filter_map { |stage| [stage, picked[stage]] if picked[stage] }
  end

  # Applies a plan to one channel. `spread` offsets the reverb's comb lengths so
  # the two sides of a stereo pair are not the same room played twice.
  def apply!(samples, plan, spread: 0)
    plan.each do |stage, options|
      options = options.merge(spread:) if stage == :reverb
      send(stage, samples, **options)
    end
    samples
  end

  def describe(plan)
    plan.map { |stage, options| "#{stage}(#{options.map { |k, v| "#{k}=#{v}" }.join(' ')})" }.join(" → ")
  end

  # Schroeder's reverberator, 1962, and still the shape of nearly every digital
  # reverb since.
  #
  # PARALLEL COMBS make the density. A comb filter is a delay fed back into
  # itself: one produces a rhythmic flutter, four at lengths sharing no common
  # factor produce a wash, because their repeats never coincide. The lengths
  # below are primes for exactly that reason -- round numbers would line up and
  # the tail would ring on a pitch.
  #
  # SERIES ALLPASSES then smear it. An allpass passes every frequency at full
  # level and only disturbs their phase, so it adds echo density without adding
  # colour, which is what turns four distinct repeats into one continuous room.
  #
  # DAMPING is the part that makes it a room rather than a machine: air and soft
  # surfaces absorb treble faster than bass, so each repeat is duller than the
  # last. A one-pole lowpass inside the feedback loop is the whole model.
  COMB_LENGTHS = [1557, 1617, 1491, 1422].freeze
  ALLPASS_LENGTHS = [225, 556].freeze

  def reverb(samples, mix: 0.3, decay: 0.84, damping: 0.34, spread: 0)
    return samples if mix <= 0.0 || samples.empty?

    wet = Array.new(samples.length, 0.0)
    COMB_LENGTHS.each do |base|
      length = base + spread
      buffer = Array.new(length, 0.0)
      index = 0
      store = 0.0
      i = 0
      while i < samples.length
        out = buffer[index]
        wet[i] += out
        # The damping lowpass lives inside the loop, so it compounds: the tenth
        # repeat has been filtered ten times, which is what an actual room does.
        store = (out * (1.0 - damping)) + (store * damping)
        buffer[index] = samples[i] + (store * decay)
        index += 1
        index = 0 if index >= length
        i += 1
      end
    end

    scale = 1.0 / COMB_LENGTHS.length
    i = 0
    while i < wet.length
      wet[i] *= scale
      i += 1
    end

    ALLPASS_LENGTHS.each do |length|
      buffer = Array.new(length, 0.0)
      index = 0
      i = 0
      while i < wet.length
        buffered = buffer[index]
        out = -wet[i] + buffered
        buffer[index] = wet[i] + (buffered * 0.5)
        wet[i] = out
        index += 1
        index = 0 if index >= length
        i += 1
      end
    end

    dry = 1.0 - mix
    i = 0
    while i < samples.length
      samples[i] = (samples[i] * dry) + (wet[i] * mix)
      i += 1
    end
    samples
  end

  # The Space Echo, which is a tape loop and behaves like one.
  #
  # Three things separate it from a digital delay, and all three are the tape.
  #
  # WOW. The capstan is never perfectly steady, so the playback head reads at a
  # slightly wrong speed and every repeat is fractionally out of tune with the
  # one before. The read position here is modulated by a slow sine and the
  # sample is interpolated between neighbours, which is what produces that
  # pitch smear rather than a clean copy.
  #
  # LOSS. Tape and the record/playback heads roll off the top, and the signal
  # goes round the loop again and again, so each repeat is duller. The one-pole
  # in the feedback path is that.
  #
  # SATURATION. The tape is being driven, so loud repeats compress rather than
  # clip. tanh is the standard stand-in and is what keeps a long feedback tail
  # from turning into a scream.
  def space_echo(samples, time: 0.28, feedback: 0.42, mix: 0.32, damping: 0.28,
                 wow_hz: 0.7, wow_ms: 1.6)
    return samples if mix <= 0.0 || samples.empty?

    base = (time * RATE).to_i.clamp(64, RATE * 2)
    depth = (wow_ms / 1000.0) * RATE
    length = base + depth.ceil + 4
    buffer = Array.new(length, 0.0)
    write = 0
    store = 0.0
    two_pi = 2.0 * Math::PI

    i = 0
    while i < samples.length
      offset = base + (depth * Math.sin(two_pi * wow_hz * i / RATE))
      read = write - offset
      read += length while read.negative?
      lower = read.floor
      frac = read - lower
      a = buffer[lower % length]
      b = buffer[(lower + 1) % length]
      echo = a + ((b - a) * frac)

      store = (echo * (1.0 - damping)) + (store * damping)
      buffer[write] = Math.tanh(samples[i] + (store * feedback))
      samples[i] += echo * mix

      write += 1
      write = 0 if write >= length
      i += 1
    end
    samples
  end

  # A phaser is a stack of allpass filters whose corner frequency is moving.
  #
  # Each allpass leaves the level alone and shifts the phase, and phase shift
  # varies with frequency -- so mixing the output back with the input cancels
  # wherever the two are opposed and reinforces where they agree. Those notches
  # sweep as the LFO moves them, and the sound is the notches, not the filters.
  # An even number of stages, because each pair makes one notch.
  def phaser(samples, rate_hz: 0.35, depth: 0.7, stages: 6, feedback: 0.4, mix: 0.5)
    return samples if mix <= 0.0 || samples.empty?

    z = Array.new(stages, 0.0)
    last = 0.0
    two_pi = 2.0 * Math::PI
    i = 0
    while i < samples.length
      sweep = 0.5 + (0.5 * Math.sin(two_pi * rate_hz * i / RATE))
      # 200 Hz to about 1.6 kHz, which is where a phaser is audible as movement
      # rather than as a tone change.
      corner = 200.0 * (8.0**(sweep * depth))
      coefficient = (1.0 - (corner / (RATE / 2.0))) / (1.0 + (corner / (RATE / 2.0)))

      value = samples[i] + (last * feedback)
      s = 0
      while s < stages
        out = (coefficient * value) + z[s]
        z[s] = value - (coefficient * out)
        value = out
        s += 1
      end
      last = value
      samples[i] += value * mix
      i += 1
    end
    samples
  end

  # Amplitude moving under a slow LFO. The oldest effect there is -- it is what
  # a Rhodes' tremolo does and what a rotating speaker does to level -- and the
  # one that most reliably stops a held note sounding dead.
  def tremolo(samples, rate_hz: 4.2, depth: 0.4, shape: :sine)
    return samples if depth <= 0.0 || samples.empty?

    two_pi = 2.0 * Math::PI
    i = 0
    while i < samples.length
      phase = (rate_hz * i / RATE) % 1.0
      lfo = shape == :square ? (phase < 0.5 ? 1.0 : -1.0) : Math.sin(two_pi * phase)
      samples[i] *= 1.0 - (depth * 0.5 * (1.0 - lfo))
      i += 1
    end
    samples
  end

  # Bit depth and sample rate thrown away on purpose.
  #
  # Quantising to fewer bits adds distortion that tracks the signal, and holding
  # each sample for several periods folds everything above the new Nyquist back
  # down as inharmonic aliasing. Both are faults, and both are the sound of
  # every sampler made before about 1990.
  def crush(samples, bits: 10, hold: 3, mix: 0.6)
    return samples if mix <= 0.0 || samples.empty?

    levels = (2**bits.clamp(2, 16)).to_f
    held = 0.0
    i = 0
    while i < samples.length
      held = samples[i] if (i % hold).zero?
      crushed = ((held * levels).round / levels)
      samples[i] = (samples[i] * (1.0 - mix)) + (crushed * mix)
      i += 1
    end
    samples
  end

  # A wave folder, which is not a clipper: where a clipper flattens a peak, this
  # turns it back on itself, so the harmonics it adds keep growing with the
  # input instead of settling. West-coast synthesis used this instead of a
  # filter and it is why a Buchla sounds nothing like a Moog.
  def fold(samples, amount: 1.8, mix: 0.5)
    return samples if mix <= 0.0 || samples.empty?

    i = 0
    while i < samples.length
      x = samples[i] * amount
      x = (x - 4.0 * ((x / 4.0 + 0.5).floor)).abs * 2.0 - 1.0 if x.abs > 1.0
      samples[i] = (samples[i] * (1.0 - mix)) + (x * mix)
      i += 1
    end
    samples
  end

  # A chorus is a delay short enough that the ear hears it as one voice rather
  # than two, with its delay time moving. What arrives is the sound plus a copy
  # of itself a few milliseconds and a few cents away, which is the whole of
  # what makes one oscillator sound like several players.
  def chorus(samples, rate_hz: 0.6, depth_ms: 4.5, mix: 0.35, centre_ms: 12.0)
    return samples if mix <= 0.0 || samples.empty?

    centre = (centre_ms / 1000.0) * RATE
    depth = (depth_ms / 1000.0) * RATE
    length = (centre + depth).ceil + 4
    buffer = Array.new(length, 0.0)
    write = 0
    two_pi = 2.0 * Math::PI

    i = 0
    while i < samples.length
      buffer[write] = samples[i]
      offset = centre + (depth * Math.sin(two_pi * rate_hz * i / RATE))
      read = write - offset
      read += length while read.negative?
      lower = read.floor
      frac = read - lower
      a = buffer[lower % length]
      b = buffer[(lower + 1) % length]
      samples[i] += (a + ((b - a) * frac)) * mix

      write += 1
      write = 0 if write >= length
      i += 1
    end
    samples
  end
end
