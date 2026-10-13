# frozen_string_literal: true

# ------------------------------------------------------------- processors
# Every filter and effect of the engine as an object that keeps its state between calls. A signal
# cut into blocks and handed to one of these comes out as it would from a single call, so the whole
# render and the streamed render are the same arithmetic. Each has `process(block)` returning a block
# of the same length (the echo, which rings on, is told to run on).
module Stream
  TAU = 2 * Math::PI

  def self.db(x) = 10.0**(x / 20.0)

  # One pole: the signal follows itself at a rate set by the cutoff. nil cutoff passes everything.
  class Lowpass
    def initialize(cutoff)
      @a = cutoff && (1.0 / SAMPLE_RATE / ((1.0 / (TAU * cutoff)) + (1.0 / SAMPLE_RATE)))
      @y = 0.0
    end

    def step(x)
      @y += @a * (x - @y)
    end

    def process(buf)
      return buf unless @a

      buf.map { |x| step(x) }
    end
  end

  # A DC-blocking highpass.
  class Highpass
    def initialize(cutoff)
      @a = 1.0 / (1.0 + (TAU * cutoff / SAMPLE_RATE))
      @y = @prev = 0.0
    end

    def step(x)
      @y = @a * (@y + x - @prev)
      @prev = x
      @y
    end

    def process(buf) = buf.map { |x| step(x) }
  end

  # A feed-forward compressor: the level follows the signal, over the threshold the gain falls.
  class Compressor
    def initialize(threshold, ratio, attack_ms, release_ms, makeup)
      @up = 1.0 - Math.exp(-1.0 / (attack_ms / 1000.0 * SAMPLE_RATE))
      @down = 1.0 - Math.exp(-1.0 / (release_ms / 1000.0 * SAMPLE_RATE))
      @limit = Stream.db(threshold)
      @slope = 1.0 - (1.0 / ratio)
      @gain = Stream.db(makeup)
      @level = 0.0
    end

    def step(x)
      a = x.abs
      @level += (a > @level ? @up : @down) * (a - @level)
      over = @level > @limit ? (@limit / @level)**@slope : 1.0
      x * over * @gain
    end

    def process(buf) = buf.map { |x| step(x) }
  end

  # Sample-rate reduction by `factor` (hold each value) and rounding to `bits` of resolution.
  class Crush
    def initialize(bits, factor)
      @levels = 2.0**(bits - 1)
      @factor = factor
      @held = 0.0
      @clock = factor
    end

    def step(x)
      if @clock >= @factor
        @held = (x * @levels).round / @levels
        @clock -= @factor
      end
      @clock += 1.0
      @held
    end

    def process(buf) = buf.map { |x| step(x) }
  end

  # The summing colour: a soft knee that bends only the peaks over a touch of low warmth.
  class Vcs
    def initialize(amount)
      @amount = amount.clamp(0.0, 1.0)
      @drive = 1.0 + (2.0 * @amount)
      @warm = Lowpass.new(180.0)
    end

    def step(x) = Math.tanh((x + (0.12 * @amount * @warm.step(x))) * @drive) / @drive

    def process(buf) = @amount.positive? ? buf.map { |x| step(x) } : buf
  end

  # Four feedback combs in series, the room of FX.reverb. Nothing is normalised, so the result
  # does not depend on how much of the signal has arrived.
  class Reverb
    DELAYS = [0.0297, 0.0371, 0.0411, 0.0437].freeze
    GAINS = [0.70, 0.65, 0.60, 0.55].freeze

    def initialize(amount)
      @amount = amount
      @lines = DELAYS.map { |d| Array.new((d * SAMPLE_RATE).to_i, 0.0) }
      @at = 0
    end

    def process(buf)
      return buf if @amount.nil? || @amount <= 0

      buf.map do |x|
        v = x
        @lines.each_with_index do |line, k|
          slot = @at % line.size
          v += line[slot] * GAINS[k] * @amount
          line[slot] = v
        end
        @at += 1
        v
      end
    end
  end

  # A spring tank: the signal, band limited to what a spring passes, goes round a short loop
  # through a chain of allpass sections. The sections delay the highs more than the lows, which is
  # the chirp of a spring, and the loop turns it into a splashing tail. Static: no modulation.
  class Spring
    LOOP = (0.037 * SAMPLE_RATE).round
    COEFF = 0.62

    def initialize(amount)
      @amount = amount
      @low = Lowpass.new(3800)
      @high = Highpass.new(160.0)
      @ring = Array.new(LOOP, 0.0)
      @states = Array.new(12, 0.0)
      @smooth = 0.0
      @at = 0
    end

    def process(buf)
      return buf if @amount.nil? || @amount <= 0 || buf.empty?

      buf.map do |x|
        v = @high.step(@low.step(x)) + (0.6 * @ring[@at % LOOP])
        @states.each_index do |k|
          y = (COEFF * v) + @states[k]
          @states[k] = v - (COEFF * y)
          v = y
        end
        @smooth += 0.45 * (v - @smooth)
        @ring[@at % LOOP] = @smooth
        @at += 1
        x + (@amount * @smooth)
      end
    end
  end

  # A space echo: playback heads read one loop at 1x, 2x and 3x the base delay, summed, darkened
  # by a lowpass and a mild saturation, and fed back. `process` takes a block of input and returns
  # the dry plus echo for it; ask for blocks of silence to let the repeats ring on. `resets` are
  # absolute sample indices where the heads are cleared, `send` the hand on the send knob.
  class EchoLine
    MAX_INTENSITY = 0.9

    def initialize(delay:, heads: [1, 2], intensity: 0.5, volume: 0.45, lowpass: 3200, saturation: 0.35, reverb: 0.0, resets: [], send: nil)
      @intensity = intensity.to_f.clamp(0.0, MAX_INTENSITY)
      @d = [(delay * SAMPLE_RATE).round, 1].max
      @heads = heads
      @ring = Array.new((heads.max * @d) + 1, 0.0)
      @cutoff = lowpass ? 1.0 / ((2 * Math::PI * lowpass * (1.0 / SAMPLE_RATE)) + 1.0) : 0.0
      @drive = 1.0 + (2.0 * saturation)
      @share = 1.0 / heads.size
      @volume = volume
      @cuts = resets.to_h { |at| [at, true] }
      @send = send
      @room = reverb.to_f.positive? ? Reverb.new(reverb) : nil
      @y = 0.0
      @n = 0
    end

    # What the heads give back for a block of input, before any room is put on it.
    def wet(block)
      Array.new(block.size) do |i|
        if @cuts[@n] # a chord changes: what the heads still hold belongs to the old chord and goes quiet
          @ring.fill(0.0)
          @y = 0.0
        end
        taps = 0.0
        @heads.each { |h| taps += @ring[(@n - (h * @d)) % @ring.size] }
        @y += (1.0 - @cutoff) * ((Math.tanh(taps * @share * @drive) / @drive) - @y)
        fed = block[i]
        fed *= @send.call(@n) if @send
        @ring[@n % @ring.size] = fed + (@intensity * @y)
        @n += 1
        @y
      end
    end

    def process(block)
      heard = wet(block)
      heard = @room.process(heard) if @room
      Array.new(block.size) { |i| block[i] + (@volume * heard[i]) }
    end
  end

  # The 12-bit sampler colour: a drive into a hard band limit, bit and rate reduction, a little
  # hiss and dust, a compressor and a limiter. One instance of it; the engine runs one to three.
  class Sonitex
    def initialize(preset, seed)
      @p = preset
      @rng = seed.is_a?(Random) ? seed : Random.new(seed)
      @pre = Lowpass.new(preset.fetch('dist_pre_lp'))
      @bump_low = Lowpass.new(preset.fetch('head_bump_hz'))
      @bump = Stream.db(preset.fetch('head_bump_db')) - 1.0
      @crush = Crush.new(preset.fetch('crush_bits'), preset.fetch('crush_sr'))
      @post = Lowpass.new(preset.fetch('crush_post_lp'))
      @hf = [Lowpass.new(preset.fetch('hf_rolloff')), Lowpass.new(preset.fetch('hf_rolloff'))]
      @lf = Highpass.new(preset.fetch('lf_rolloff'))
      @comp = Compressor.new(preset.fetch('out_comp_threshold'), preset.fetch('out_comp_ratio'), 12.0, 120.0, preset.fetch('out_comp_makeup') - 1.0)
      @pop = 0.0
    end

    def process(buf)
      p = @p
      drive = p.fetch('dist_drive')
      mix = p.fetch('dist_mix')
      dc = p.fetch('dist_dc')
      tail = Math.tanh(dc)
      crush_mix = p.fetch('crush_mix')
      hiss = p.fetch('hiss_amp')
      pops = p.fetch('pop_rate')
      pop_amp = p.fetch('pop_amp')
      limit = p.fetch('limit')
      level = p.fetch('level_out')
      buf.map do |x|
        wet = Math.tanh((@pre.step(x) * drive) + dc) - tail
        out = (x * (1.0 - mix)) + (wet * mix / [drive, 1.0].max * 1.2)
        out += @bump * @bump_low.step(out)
        crushed = @post.step(@crush.step(out))
        out = (out * (1.0 - crush_mix)) + (crushed * crush_mix)
        out = @lf.step(@hf[1].step(@hf[0].step(out)))
        @pop = (@rng.rand < pops ? (@rng.rand < 0.5 ? -pop_amp : pop_amp) : @pop) * 0.985
        out = out + (((@rng.rand * 2) - 1) * hiss) + (@pop * 0.4)
        limit * Math.tanh(@comp.step(out) / limit) * level
      end
    end
  end
  # Up to three Sonitex passes in series, each with a random stream of its own.
  class SonitexStack
    def initialize(preset, instances, seed)
      @passes = Array.new(instances.clamp(1, 3)) { |k| Sonitex.new(preset, Random.new(seed + (k * 7919))) }
    end

    def process(buf) = @passes.inject(buf) { |out, pass| pass.process(out) }
  end

  # The lowpass the kit voices use, k = 1 - exp(-2 pi f / rate).
  class SmoothLowpass
    def initialize(hz)
      @k = 1.0 - Math.exp(-TAU * hz / SAMPLE_RATE)
      @y = 0.0
    end

    def process(buf) = buf.map { |x| @y += @k * (x - @y) }
  end

  # The chords duck on every kick: the gain at an absolute sample is the deepest dip any kick
  # within four releases before it still makes, so it needs no state and no block size.
  class Duck
    def initialize(kick_times, amount, release_seconds)
      @starts = kick_times.map { |t| (t * SAMPLE_RATE).to_i }.sort
      @amount = amount
      @release = release_seconds * SAMPLE_RATE
      @reach = (@release * 4).to_i
    end

    def apply(block, from)
      return block if @starts.empty? || @amount.zero?

      stop = from + block.size
      near = @starts.select { |s| s < stop && s + @reach > from }
      return block if near.empty?

      block.each_with_index.map do |v, i|
        at = from + i
        dip = 1.0
        near.each do |s|
          n = at - s
          g = n.negative? || n >= @reach ? 1.0 : 1.0 - (@amount * Math.exp(-n / @release))
          dip = g if g < dip
        end
        v * dip
      end
    end
  end

  # Notes and hits that start at absolute samples, read out a block at a time. An entry is
  # [start, make, gain, swell]: `make` gives a Reader when its sample comes up, `gain` scales it and
  # `swell` (or nil) is a proc from an absolute sample to a further gain.
  class Bank
    Entry = Struct.new(:start, :make, :gain, :swell)

    def initialize(entries)
      @pending = entries.sort_by(&:start)
      @active = []
    end

    def finished? = @pending.empty? && @active.empty?

    # The sample at which the last pending note will have started.
    def last_start = @pending.last&.start || 0

    def block(from, count)
      out = Array.new(count, 0.0)
      stop = from + count
      @active.concat(@pending.shift(@pending.index { |e| e.start >= stop } || @pending.size).map { |e| [e, e.make.call] })
      @active.reject! do |entry, reader|
        offset = [entry.start - from, 0].max
        samples = reader.read(count - offset)
        gain = entry.gain
        if entry.swell
          samples.each_with_index { |v, j| out[offset + j] += v * gain * entry.swell.call(from + offset + j) }
        else
          samples.each_with_index { |v, j| out[offset + j] += v * gain }
        end
        reader.done?
      end
      out
    end
  end
end
