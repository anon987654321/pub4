# frozen_string_literal: true

# ------------------------------------------------------------------ stages
# The optional effects a profile lists in its `chain`. Each is a processor for one channel with
# memory of its own, `process(block, from)`, where `from` is the block's first sample in the pass; the
# builder runs one for each channel with a seed of its own, so the two channels are not copies.
# They sit after the colour and before the echo: tone, then dynamics, then colour, then space.
# None of them uses a low-frequency oscillator to move a pitch, a delay or a level; the
# shimmer's pitch shifter and the ring modulator's carrier are what they are, a read pointer and a
# fixed frequency, and the sweeps and swells are events with a start and a length. The cost of
# each, in seconds of work for a second of audio on this Mac, with YJIT, is in the data beside it.
module Stages
  TAU = 2 * Math::PI

  # Dry and wet, the way most of them end.
  def self.blend(dry, wet, mix) = dry.each_index.map { |i| dry[i] + (mix * (wet[i] - dry[i])) }

  # ------------------------------------------------------------ pitch shifter
  # Two read pointers move through a short delay line at a different rate than the write pointer,
  # each faded in and out by a Hann window half a cycle apart, so the sum is steady. Ratio 2 is an octave up.
  class Pitch
    def initialize(ratio, window: 0.06)
      @ratio = ratio
      @size = (window * SAMPLE_RATE).round
      @line = Array.new((@size * 2) + 4, 0.0)
      @n = 0
      @phase = 0.0
      @rate = (1.0 - ratio).to_f / @size
    end

    def step(x)
      len = @line.size
      @line[@n % len] = x
      sum = 0.0
      [0.0, 0.5].each do |offset|
        p = (@phase + offset) % 1.0
        delay = (@size * p) + 1.0
        pos = @n - delay
        base = pos.floor
        frac = pos - base
        a = @line[base % len]
        b = @line[(base + 1) % len]
        sum += (a + ((b - a) * frac)) * (0.5 - (0.5 * Math.cos(TAU * p)))
      end
      @phase = (@phase + @rate) % 1.0
      @n += 1
      sum
    end
  end

  # ------------------------------------------------------------ the room
  # The Freeverb: four combs with damping in the loop, in parallel, then two allpass. `side` moves
  # the delays a little so the right channel is another room.
  class Room
    COMBS = [1116, 1188, 1277, 1356].freeze
    ALLPASS = [556, 441].freeze

    def initialize(decay: 0.84, damp: 0.35, side: 0)
      @combs = COMBS.map { |d| [Array.new(d + (side * 23), 0.0), 0, 0.0] }
      @allpass = ALLPASS.map { |d| [Array.new(d + (side * 23), 0.0), 0] }
      @feedback = decay
      @damp = damp
    end

    def step(x)
      sum = 0.0
      @combs.each do |c|
        line, at, held = c
        out = line[at]
        held = (out * (1.0 - @damp)) + (held * @damp)
        line[at] = (x * 0.015) + (held * @feedback)
        c[1] = (at + 1) % line.size
        c[2] = held
        sum += out
      end
      @allpass.each do |a|
        line, at = a
        buffered = line[at]
        out = buffered - sum
        line[at] = sum + (buffered * 0.5)
        a[1] = (at + 1) % line.size
        sum = out
      end
      sum
    end
  end

  # A plate or a room, after the Freeverb.
  class Plate
    def initialize(spec, seed, side)
      @room = Room.new(decay: spec.fetch('decay', 0.84), damp: spec.fetch('damp', 0.35), side:)
      @mix = spec.fetch('mix', 0.25)
      @gain = spec.fetch('gain', 30.0)
    end

    def process(block, _from = 0) = block.map { |x| x + (@mix * @room.step(x) * @gain) }
  end

  # The room with an octave-up feedback: what rings in the room is shifted up an octave and fed
  # into the room again, so each round of the tail is higher and quieter.
  class Shimmer
    def initialize(spec, _seed, side)
      @room = Room.new(decay: spec.fetch('decay', 0.88), damp: spec.fetch('damp', 0.45), side:)
      @pitch = Pitch.new(spec.fetch('ratio', 2.0))
      @feedback = spec.fetch('feedback', 0.45)
      @mix = spec.fetch('mix', 0.3)
      @gain = spec.fetch('gain', 30.0)
      @shifted = 0.0
    end

    def process(block, _from = 0)
      block.map do |x|
        wet = @room.step(x + (@feedback * @shifted))
        @shifted = @pitch.step(wet)
        x + (@mix * (wet + (0.5 * @shifted)) * @gain)
      end
    end
  end

  # ------------------------------------------------------------ granular
  # A cloud of Hann-windowed grains from the last couple of seconds of the signal: each grain
  # starts a random way back (the spray), lasts sixty to two hundred milliseconds, and may be an
  # octave up, an octave down, or played backwards. The draws come from a stream seeded for the
  # channel, one per grain, so the cloud is the same however the signal is cut into blocks.
  class Granular
    HISTORY = (2.5 * SAMPLE_RATE).round

    def initialize(spec, seed, _side)
      @rng = Random.new(seed)
      @line = Array.new(HISTORY, 0.0)
      @n = 0
      @density = spec.fetch('density', 9.0)
      @min = (spec.fetch('min_ms', 60) * SAMPLE_RATE / 1000.0).round
      @max = (spec.fetch('max_ms', 200) * SAMPLE_RATE / 1000.0).round
      @spray = spec.fetch('spray', 1.4)
      @up = spec.fetch('up', 0.18)
      @down = spec.fetch('down', 0.10)
      @reverse = spec.fetch('reverse', 0.25)
      @mix = spec.fetch('mix', 0.35)
      @grains = []
      @next_grain = 0
    end

    def process(block, _from = 0)
      block.map do |x|
        @line[@n % HISTORY] = x
        spawn if @n >= @next_grain
        sum = 0.0
        @grains.reject! do |g|
          sum += grain_sample(g)
          g[:age] >= g[:length]
        end
        @n += 1
        x + (@mix * sum)
      end
    end

    private

    def spawn
      @next_grain = @n + ((SAMPLE_RATE / @density) * (0.5 + @rng.rand)).round
      length = @min + @rng.rand(@max - @min + 1)
      roll = @rng.rand
      rate = roll < @up ? 2.0 : (roll < @up + @down ? 0.5 : 1.0)
      backward = @rng.rand < @reverse
      reach = (length * rate).ceil + 8
      back = reach + (@rng.rand * @spray * SAMPLE_RATE).round
      back = [back, HISTORY - 8].min
      start = backward ? @n - back + reach : @n - back
      @grains << { pos: start.to_f, rate: backward ? -rate : rate, age: 0, length:, gain: 0.5 / Math.sqrt([@density * length / SAMPLE_RATE, 1.0].max) }
    end

    def grain_sample(g)
      pos = g[:pos]
      base = pos.floor
      frac = pos - base
      a = @line[base % HISTORY]
      b = @line[(base + 1) % HISTORY]
      window = 0.5 - (0.5 * Math.cos(TAU * g[:age] / g[:length]))
      g[:pos] = pos + g[:rate]
      g[:age] += 1
      (a + ((b - a) * frac)) * window * g[:gain]
    end
  end

  # ------------------------------------------------------------ the simple ones
  class Crush
    def initialize(spec, _seed, _side)
      @crush = Stream::Crush.new(spec.fetch('bits', 10), spec.fetch('factor', 2.0))
      @mix = spec.fetch('mix', 0.5)
    end

    def process(block, _from = 0) = Stages.blend(block, @crush.process(block), @mix)
  end

  # A triangle fold: past one the signal turns back, and again, so a larger input grows more harmonics.
  class Folder
    def initialize(spec, _seed, _side)
      @gain = spec.fetch('gain', 2.4)
      @mix = spec.fetch('mix', 0.3)
    end

    def process(block, _from = 0)
      block.map do |x|
        y = x * @gain
        folded = (4.0 * ((0.25 * y) + 0.25 - ((0.25 * y) + 0.25).round).abs) - 1.0
        x + (@mix * ((folded / @gain) - x))
      end
    end
  end

  # A ring modulator at one fixed frequency.
  class RingMod
    def initialize(spec, _seed, _side)
      @step = TAU * spec.fetch('hz', 140.0) / SAMPLE_RATE
      @mix = spec.fetch('mix', 0.2)
    end

    def process(block, from = 0)
      block.each_with_index.map { |x, i| x + (@mix * ((x * Math.sin(@step * (from + i))) - x)) }
    end
  end

  # A frequency shifter: the signal and its quadrature twin, from two chains of allpass sections
  # whose phases are ninety degrees apart, are multiplied by a cosine and a sine of the shift and
  # subtracted, which moves every partial by the same number of hertz and breaks the harmonic series.
  class FreqShift
    ONE = [0.6923878, 0.9360654322959, 0.9882295226860, 0.9987488452737].freeze
    TWO = [0.4021921162426, 0.8561710882420, 0.9722909545651, 0.9952884791278].freeze

    def initialize(spec, _seed, _side)
      @step = TAU * spec.fetch('hz', 7.0) / SAMPLE_RATE
      @mix = spec.fetch('mix', 0.5)
      @a = ONE.map { |c| c * c }
      @b = TWO.map { |c| c * c }
      @sa = Array.new(@a.size) { [0.0, 0.0, 0.0, 0.0] }
      @sb = Array.new(@b.size) { [0.0, 0.0, 0.0, 0.0] }
      @held = 0.0
    end

    def process(block, from = 0)
      block.each_with_index.map do |x, i|
        ahead = chain(@a, @sa, x)
        imag = chain(@b, @sb, x)
        real = @held # the first branch runs one sample late: that is what puts the two ninety degrees apart
        @held = ahead
        phase = @step * (from + i)
        shifted = (real * Math.cos(phase)) + (imag * Math.sin(phase))
        x + (@mix * (shifted - x))
      end
    end

    private

    # Allpass sections in z^-2, (a - z^-2) / (1 - a z^-2): y = a*x - x[n-2] + a*y[n-2]. A section keeps
    # [x[n-1], x[n-2], y[n-1], y[n-2]].
    def chain(coeffs, states, x)
      coeffs.each_index do |k|
        a = coeffs[k]
        s = states[k]
        y = (a * x) - s[1] + (a * s[3])
        s[1] = s[0]
        s[0] = x
        s[3] = s[2]
        s[2] = y
        x = y
      end
      x
    end
  end

  # The last stretch of each segment, reversed and swelling in beneath the next: the signal of
  # one segment is kept, and played back backwards through the next, rising from nothing.
  class ReverseEcho
    def initialize(spec, _seed, _side)
      @length = (spec.fetch('seconds', 1.0) * SAMPLE_RATE).round
      @mix = spec.fetch('mix', 0.4)
      @kept = Array.new(@length, 0.0)
      @played = Array.new(@length, 0.0)
      @n = 0
    end

    def process(block, _from = 0)
      block.map do |x|
        at = @n % @length
        @kept[at] = x
        swell = (at.to_f / @length)**2
        out = x + (@mix * @played[@length - 1 - at] * swell)
        if at == @length - 1
          @played, @kept = @kept, @played
        end
        @n += 1
        out
      end
    end
  end

  # The tape stops: in the last `seconds` before the pass ends the read pointer slows to nothing,
  # the pitch falling with it, and the sound is gone.
  class TapeStop
    def initialize(spec, _seed, _side, end_sample: 0)
      @length = (spec.fetch('seconds', 0.8) * SAMPLE_RATE).round
      @end = end_sample
      @line = Array.new(@length + 8192, 0.0)
      @n = 0
      @pos = nil
      @speed = 1.0
    end

    def process(block, from = 0)
      return block if @end <= 0

      len = @line.size
      block.each_with_index.map do |x, i|
        at = from + i
        @line[@n % len] = x
        @n += 1
        out = x
        if at >= @end - @length
          @pos ||= @n - 1.0
          progress = [(at - (@end - @length)).to_f / @length, 1.0].min
          @speed = (1.0 - progress)**1.5
          base = @pos.floor
          frac = @pos - base
          a = @line[base % len]
          b = @line[(base + 1) % len]
          out = (a + ((b - a) * frac)) * (1.0 - (progress**3))
          @pos += @speed
        end
        out
      end
    end
  end

  # A filter sweep that is an event, not an oscillator: every `every_bars` bars the cutoff falls
  # from the top to `low_hz` over `bars` bars and comes back over the same. The cutoff is a function
  # of the sample's place in the pass, set afresh every 64 samples, so how the pass is cut into
  # blocks makes no difference.
  class Sweep
    STEP = 64

    def initialize(spec, _seed, _side, bar_samples: 1)
      @bar = bar_samples
      @every = spec.fetch('every_bars', 8)
      @bars = spec.fetch('bars', 2)
      @low = spec.fetch('low_hz', 500.0)
      @top = spec.fetch('top_hz', 16_000.0)
      @y = 0.0
      @a = 1.0
    end

    def process(block, from = 0)
      block.each_with_index.map do |x, i|
        at = from + i
        @a = 1.0 - Math.exp(-TAU * cutoff(at) / SAMPLE_RATE) if (at % STEP).zero?
        @y += @a * (x - @y)
      end
    end

    private

    def cutoff(at)
      into = (at.to_f / @bar) % @every
      return @top if into >= @bars * 2

      half = into < @bars ? into / @bars : ((@bars * 2) - into) / @bars
      @top * ((@low / @top)**half)
    end
  end

  # Attack and sustain: a fast and a slow follower, and the difference between them lifts the front of
  # a note or lowers what is left after it.
  class Transient
    def initialize(spec, _seed, _side)
      @attack = 10.0**(spec.fetch('attack_db', 4.0) / 20.0)
      @sustain = 10.0**(spec.fetch('sustain_db', -2.0) / 20.0)
      @fast = 0.0
      @slow = 0.0
      @up_fast = 1.0 - Math.exp(-1.0 / (0.001 * SAMPLE_RATE))
      @down_fast = 1.0 - Math.exp(-1.0 / (0.02 * SAMPLE_RATE))
      @up_slow = 1.0 - Math.exp(-1.0 / (0.03 * SAMPLE_RATE))
      @down_slow = 1.0 - Math.exp(-1.0 / (0.3 * SAMPLE_RATE))
    end

    def process(block, _from = 0)
      block.map do |x|
        a = x.abs
        @fast += (a > @fast ? @up_fast : @down_fast) * (a - @fast)
        @slow += (a > @slow ? @up_slow : @down_slow) * (a - @slow)
        lean = ((@fast - @slow) / (@slow + 1e-3)).clamp(-1.0, 1.0)
        x * (lean.positive? ? 1.0 + (lean * (@attack - 1.0)) : 1.0 + (-lean * (@sustain - 1.0)))
      end
    end
  end

  # The band above six kilohertz driven into a soft clip and added back: the harmonics it makes
  # are air that was never in the recording.
  class Exciter
    def initialize(spec, _seed, _side)
      @high = Stream::Highpass.new(spec.fetch('hz', 6000.0))
      @drive = spec.fetch('drive', 3.0)
      @mix = spec.fetch('mix', 0.25)
    end

    def process(block, _from = 0)
      block.map { |x| x + (@mix * Math.tanh(@high.step(x) * @drive) / @drive * 2.0) }
    end
  end

  # Bandpass resonators at inharmonic partials with a high Q, the colour of a mouth without its
  # vowels. The bank rings on what is put into it and is added to the dry signal.
  class CombBank
    RATIOS = [1.0, 2.76, 5.40, 8.93, 13.34].freeze

    def initialize(spec, _seed, _side)
      base = spec.fetch('hz', 220.0)
      q = spec.fetch('q', 18.0)
      @bands = RATIOS.map { |r| Tape::Biquad.bandpass([base * r, SAMPLE_RATE * 0.45].min, q) }
      @mix = spec.fetch('mix', 0.35)
    end

    def process(block, _from = 0)
      rung = @bands.map { |band| band.process(block) }
      block.each_index.map { |i| block[i] + (@mix * rung.sum { |r| r[i] } / @bands.size * 2.0) }
    end
  end

  KINDS = {
    'plate' => Plate, 'shimmer' => Shimmer, 'granular' => Granular, 'crush' => Crush, 'folder' => Folder, 'ringmod' => RingMod,
    'freqshift' => FreqShift, 'reverse_echo' => ReverseEcho, 'tapestop' => TapeStop, 'sweep' => Sweep, 'transient' => Transient,
    'exciter' => Exciter, 'comb_bank' => CombBank
  }.freeze

  # One stage of a profile's chain, as a Pair of processors for `channels` channels. A row of the
  # chain is a name, or { 'stage' => name, ...overrides } laid over the stage's defaults.
  def self.build(row, defaults, channels:, seed:, end_sample: 0, bar_samples: 1)
    row = { 'stage' => row } if row.is_a?(String)
    name = row.fetch('stage')
    spec = defaults.fetch(name) { raise ArgumentError, "no stage #{name.inspect}" }.merge(row.reject { |k, _| k == 'stage' })
    klass = KINDS.fetch(name)
    parts = Array.new(channels) do |c|
      channel_seed = Zlib.crc32("#{seed}:#{name}:#{c}")
      case name
      when 'tapestop' then klass.new(spec, channel_seed, c, end_sample:)
      when 'sweep' then klass.new(spec, channel_seed, c, bar_samples:)
      else klass.new(spec, channel_seed, c)
      end
    end
    Chained.new(parts)
  end

  # A stage on each channel; a block is a frame.
  class Chained
    def initialize(parts) = @parts = parts

    def process(frame, from = 0) = frame.each_with_index.map { |channel, c| @parts[c].process(channel, from) }
  end
end
