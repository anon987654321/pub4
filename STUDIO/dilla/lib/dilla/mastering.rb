# frozen_string_literal: true

# --------------------------------------------------------------- mastering
# The last stages before the tape stack, in the order a console has them: tone, then dynamics,
# then level, with the limiter after the tape. Every stage works on a frame, [mono] or
# [left, right], keeps its state between blocks, and gives the same samples however the signal is cut.
#
#   EQ              a cut in the low mids and a shelf of air, and a dynamic cut that deepens when
#                   the low mids build up
#   multiband       three bands split by Linkwitz-Riley crossovers, each compressed, the detector
#                   linked between the channels
#   parallel        a hard compressed copy mixed under the dry signal, the New York way
#   glue            a gentle bus compressor whose release is half a beat of the tempo
#   loudness        a gain to the target level in LUFS, measured with K-weighting and gating
#   soft clip       the peaks bent before the limiter sees them
#   (the tape stack)
#   limiter         look-ahead, with the peak found on a four times oversampled signal, so the
#                   ceiling holds in dB true peak and not only in samples
module Mastering
  def self.db(x) = 10.0**(x / 20.0)

  def self.to_db(ratio) = 20.0 * Math.log10([ratio, 1e-12].max)

  # ------------------------------------------------------------------ loudness
  module Loudness
    HOP = (0.1 * SAMPLE_RATE).round # a 400 ms block every 100 ms

    # The K-weighting of ITU-R BS.1770: a high shelf of +4 dB near 1.7 kHz, then a highpass at 38 Hz.
    def self.k_weighting
      shelf = begin
        k = Math.tan(Math::PI * 1681.974450955533 / SAMPLE_RATE)
        q = 0.7071752369554196
        vh = 10.0**(3.999843853973347 / 20.0)
        vb = vh**0.4996667741545416
        a0 = 1.0 + (k / q) + (k * k)
        Tape::Biquad.new([(vh + (vb * k / q) + (k * k)) / a0, 2.0 * ((k * k) - vh) / a0, (vh - (vb * k / q) + (k * k)) / a0],
                         [1.0, 2.0 * ((k * k) - 1.0) / a0, (1.0 - (k / q) + (k * k)) / a0])
      end
      high = begin
        k = Math.tan(Math::PI * 38.13547087602444 / SAMPLE_RATE)
        q = 0.5003270373238773
        a0 = 1.0 + (k / q) + (k * k)
        Tape::Biquad.new([1.0, -2.0, 1.0], [a0, 2.0 * ((k * k) - 1.0), 1.0 - (k / q) + (k * k)])
      end
      [shelf, high]
    end

    # A running meter: feed it frames, ask for the momentary or integrated loudness.
    class Meter
      def initialize(channels)
        @filters = Array.new(channels) { Loudness.k_weighting }
        @sums = Array.new(channels, 0.0)
        @held = 0
        @hops = [] # mean square summed over the channels, for each hop
      end

      # The mean square of every hundred milliseconds, closed exactly on the hop, whatever the size of the frame.
      def feed(frame)
        count = frame.first.size
        at = 0
        while at < count
          take = [HOP - @held, count - at].min
          frame.each_with_index do |channel, c|
            shelf, high = @filters[c]
            sum = @sums[c]
            channel[at, take].each { |x| y = high.step(shelf.step(x)); sum += y * y }
            @sums[c] = sum
          end
          @held += take
          at += take
          next if @held < HOP

          @hops << (@sums.sum / HOP)
          @sums.fill(0.0)
          @held = 0
        end
      end

      def blocks = @hops.each_cons(4).map { |four| four.sum / 4.0 }

      def self.lufs(energy) = energy.positive? ? -0.691 + (10.0 * Math.log10(energy)) : -Float::INFINITY

      def momentary = blocks.last ? Meter.lufs(blocks.last) : -Float::INFINITY

      # Integrated loudness: blocks above -70 LUFS, then above ten below the mean of those.
      def integrated
        loud = blocks.select { |e| Meter.lufs(e) > -70.0 }
        return -Float::INFINITY if loud.empty?

        floor = Meter.lufs(loud.sum / loud.size) - 10.0
        kept = loud.select { |e| Meter.lufs(e) > floor }
        kept.empty? ? -Float::INFINITY : Meter.lufs(kept.sum / kept.size)
      end
    end

    # The integrated loudness of a whole frame.
    def self.integrated(frame)
      meter = Meter.new(frame.size)
      meter.feed(frame)
      meter.integrated
    end
  end

  # ----------------------------------------------------------------- true peak
  module TruePeak
    HALF = 8

    # Windowed-sinc weights for the point `offset` of a sample step past a sample.
    def self.weights(offset)
      (-HALF + 1..HALF).map do |k|
        x = k - offset
        sinc = x.zero? ? 1.0 : Math.sin(Math::PI * x) / (Math::PI * x)
        sinc * (0.5 + (0.5 * Math.cos(Math::PI * x / (HALF + 1))))
      end
    end

    PHASES = [0.25, 0.5, 0.75].map { |o| weights(o) }.freeze

    # The highest value the signal reaches between samples, found on a four times oversampled
    # signal, looking only near the samples that are already high.
    def self.peak(samples)
      top = samples.map(&:abs).max.to_f
      return top if top.zero?

      limit = top * 0.5
      best = top
      # the ends of the array are left out: past them the signal is taken to be zero, and a sinc rings on the edge
      (HALF...(samples.size - HALF)).each do |i|
        next if samples[i].abs < limit && samples[i + 1].abs < limit

        PHASES.each do |weights|
          sum = 0.0
          weights.each_with_index { |w, j| sum += w * samples[i + j - HALF + 1] }
          best = sum.abs if sum.abs > best
        end
      end
      best
    end

    def self.db(frame) = Mastering.to_db(frame.map { |channel| peak(channel) }.max)
  end

  # --------------------------------------------------------------- the limiter
  # Look-ahead, linked between the channels. The peak of each sample is the highest of the sample
  # and of three points between it and the next, found with an eight-tap windowed sinc, which is the
  # signal as a converter will draw it. The gain that needs is spread over the look-ahead by taking
  # the lowest need in the window and averaging that over the window, so the gain is already down when
  # the peak arrives and never steps. It comes back up at the release time.
  class Limiter
    TAPS = 8
    LEAD = 4 # samples of the signal ahead of the one whose peak is being found
    PHASES = [0.25, 0.5, 0.75].map do |offset|
      Array.new(TAPS) do |j|
        x = (j - (LEAD - 1)) - offset
        sinc = x.zero? ? 1.0 : Math.sin(Math::PI * x) / (Math::PI * x)
        sinc * (0.5 + (0.5 * Math.cos(Math::PI * x / (LEAD + 1))))
      end
    end.freeze

    attr_reader :latency

    def initialize(ceiling_db: -1.0, lookahead: 64, release_ms: 120.0, channels: 2)
      @ceiling = Mastering.db(ceiling_db) * 0.995 # a margin for what eight taps miss
      @look = lookahead
      @channels = channels
      @latency = lookahead - 1 + LEAD
      @history = Array.new(channels) { Array.new(TAPS, 0.0) }
      @delay = Array.new(channels) { Array.new(@latency + 1, 0.0) }
      @deque = []
      @mins = Array.new(lookahead, 1.0)
      @mins_sum = lookahead.to_f
      @release = 1.0 - Math.exp(-1.0 / (release_ms / 1000.0 * SAMPLE_RATE))
      @env = 1.0
      @n = 0
    end

    def process(frame)
      count = frame.first.size
      out = Array.new(@channels) { Array.new(count, 0.0) }
      size = @delay.first.size
      count.times do |i|
        peak = 0.0
        @channels.times do |c|
          h = @history[c]
          h.shift
          h << frame[c][i]
          @delay[c][@n % size] = h[LEAD - 1]
          here = h[LEAD - 1].abs
          there = h[LEAD].abs
          peak = here if here > peak
          peak = [peak, between(h)].max if (here > @ceiling * 0.5 || there > @ceiling * 0.5) && (here + there) > 0.0
        end
        need = peak > @ceiling ? @ceiling / peak : 1.0
        slot = @n % @look
        # the lowest need of the last `look` samples, by a deque of the ones that could still be the lowest
        @deque.pop while !@deque.empty? && @deque.last[0] >= need
        @deque << [need, @n]
        @deque.shift while @deque.first[1] <= @n - @look
        window_min = @deque.first[0]
        @mins_sum += window_min - @mins[slot]
        @mins[slot] = window_min
        smooth = @mins_sum / @look
        @env = smooth < @env ? smooth : @env + ((smooth - @env) * @release)
        gain = [@env, smooth].min
        back = (@n - (@look - 1)) % size
        @channels.times { |c| out[c][i] = @delay[c][back] * gain }
        @n += 1
      end
      out
    end

    private

    # The highest of the three points between h[LEAD - 1] and the next sample.
    def between(h)
      best = 0.0
      PHASES.each do |weights|
        sum = 0.0
        TAPS.times { |j| sum += weights[j] * h[j] }
        best = sum.abs if sum.abs > best
      end
      best
    end
  end

  # ----------------------------------------------------------------- dynamics
  # A compressor whose detector is the highest level of any channel, so both are turned down by the
  # same amount and the image stays where it is. `apply` returns the frame and leaves the
  # state for the next block.
  class Compressor
    def initialize(threshold_db:, ratio:, attack_ms:, release_ms:, makeup_db: 0.0)
      @limit = Mastering.db(threshold_db)
      @slope = 1.0 - (1.0 / ratio)
      @up = 1.0 - Math.exp(-1.0 / (attack_ms / 1000.0 * SAMPLE_RATE))
      @down = 1.0 - Math.exp(-1.0 / (release_ms / 1000.0 * SAMPLE_RATE))
      @makeup = Mastering.db(makeup_db)
      @level = 0.0
    end

    def release_ms=(ms)
      @down = 1.0 - Math.exp(-1.0 / (ms / 1000.0 * SAMPLE_RATE))
    end

    def apply(frame)
      count = frame.first.size
      gains = Array.new(count) do |i|
        a = 0.0
        frame.each { |channel| v = channel[i].abs; a = v if v > a }
        @level += (a > @level ? @up : @down) * (a - @level)
        (@level > @limit ? (@limit / @level)**@slope : 1.0) * @makeup
      end
      frame.map { |channel| Array.new(count) { |i| channel[i] * gains[i] } }
    end
  end

  # Two Butterworth sections of one kind in series, which is a Linkwitz-Riley filter (24 dB an
  # octave), run in one loop.
  class Cascade
    def initialize(kind, hz)
      @first = Tape::Biquad.public_send(kind, hz)
      @second = Tape::Biquad.public_send(kind, hz)
    end

    def process(buf)
      a = @first
      b = @second
      buf.map { |x| b.step(a.step(x)) }
    end
  end

  # Three bands from two crossovers: a Linkwitz-Riley lowpass takes the lows and what is left
  # (the input less the lows) goes on to the second, which takes the mids from the highs the same
  # way. The three add back to the input exactly. Each band is compressed on its own.
  class Multiband
    def initialize(spec, channels)
      low_hz, high_hz = spec.fetch('crossovers')
      @cuts = Array.new(channels) { [Cascade.new(:lowpass, low_hz), Cascade.new(:lowpass, high_hz)] }
      @bands = spec.fetch('bands').map do |band|
        Compressor.new(threshold_db: band.fetch('threshold_db'), ratio: band.fetch('ratio'), attack_ms: band.fetch('attack_ms'),
                       release_ms: band.fetch('release_ms'), makeup_db: band.fetch('makeup_db', 0.0))
      end
    end

    def process(frame)
      split = frame.each_with_index.map do |channel, c|
        low = @cuts[c][0].process(channel)
        rest = channel.each_index.map { |i| channel[i] - low[i] }
        mid = @cuts[c][1].process(rest)
        [low, mid, rest.each_index.map { |i| rest[i] - mid[i] }]
      end
      bands = Array.new(3) { |b| @bands[b].apply(split.map { |s| s[b] }) }
      frame.each_index.map { |c| Array.new(frame.first.size) { |i| bands[0][c][i] + bands[1][c][i] + bands[2][c][i] } }
    end
  end

  # A cut in the low mids and a shelf of air, both static, and a dynamic cut that follows what the
  # low mids are doing: the more there is, the more of that band is taken out.
  class Equalizer
    def initialize(spec, channels)
      lm = spec.fetch('low_mid')
      air = spec.fetch('air')
      dyn = spec.fetch('dynamic')
      @chains = Array.new(channels) do
        { cut: Tape::Biquad.peaking(lm.fetch('hz'), lm.fetch('q'), lm.fetch('db')), air: Tape::Biquad.highshelf(air.fetch('hz'), air.fetch('db')),
          band: Tape::Biquad.bandpass(lm.fetch('hz'), lm.fetch('q')) }
      end
      @threshold = Mastering.db(dyn.fetch('threshold_db'))
      @range = dyn.fetch('range')
      @level = 0.0
      @up = 1.0 - Math.exp(-1.0 / (0.01 * SAMPLE_RATE))
      @down = 1.0 - Math.exp(-1.0 / (0.15 * SAMPLE_RATE))
    end

    def process(frame)
      count = frame.first.size
      statics = frame.each_with_index.map { |channel, c| channel.map { |x| @chains[c][:air].step(@chains[c][:cut].step(x)) } }
      bands = frame.each_with_index.map { |channel, c| channel.map { |x| @chains[c][:band].step(x) } }
      Array.new(frame.size) do |c|
        Array.new(count) do |i|
          if c.zero?
            a = bands.map { |b| b[i].abs }.max
            @level += (a > @level ? @up : @down) * (a - @level)
          end
          depth = ((@level / @threshold) - 1.0).clamp(0.0, 1.0) * @range
          statics[c][i] - (depth * bands[c][i])
        end
      end
    end
  end

  # ---------------------------------------------------------------- the chain
  class Chain
    attr_reader :meter, :gain_db

    def initialize(spec, channels:, bpm: 88.0, whole: false)
      @spec = spec
      @channels = channels
      @whole = whole
      @eq = Equalizer.new(spec.fetch('eq'), channels)
      @multiband = Multiband.new(spec.fetch('multiband'), channels)
      par = spec.fetch('parallel')
      @parallel = Compressor.new(threshold_db: par.fetch('threshold_db'), ratio: par.fetch('ratio'), attack_ms: par.fetch('attack_ms'),
                                 release_ms: par.fetch('release_ms'), makeup_db: par.fetch('makeup_db'))
      @parallel_mix = par.fetch('mix')
      glue = spec.fetch('glue')
      @glue = Compressor.new(threshold_db: glue.fetch('threshold_db'), ratio: glue.fetch('ratio'), attack_ms: glue.fetch('attack_ms'),
                             release_ms: 60_000.0 / bpm * glue.fetch('release_beats'), makeup_db: glue.fetch('makeup_db'))
      @glue_beats = glue.fetch('release_beats')
      @target = spec.fetch('target_lufs')
      @meter = Loudness::Meter.new(channels)
      @gain_db = 0.0
      @limiter = Limiter.new(ceiling_db: spec.fetch('ceiling_dbtp'), lookahead: spec.dig('limiter', 'lookahead') || 64,
                             release_ms: spec.dig('limiter', 'release_ms') || 120.0, channels:)
      @knee = spec.dig('clip', 'knee') || 0.7
    end

    def target=(lufs)
      @target = lufs
    end

    # The multiband and the parallel compressor are the dear stages. A show that cannot keep up with
    # the clock drops them and says so; what is left is the EQ, the glue, the level and the limiter.
    def lighten!
      @light = true
    end

    def light? = @light == true

    # The tempo the glue compressor's release follows.
    def bpm=(bpm)
      @glue.release_ms = 60_000.0 / bpm * @glue_beats
    end

    # Tone and dynamics, then the level.
    def process(frame)
      frame = @eq.process(frame)
      unless @light
        frame = @multiband.process(frame)
        dry = frame
        squashed = @parallel.apply(frame)
        frame = dry.each_index.map { |c| Array.new(dry.first.size) { |i| dry[c][i] + (@parallel_mix * squashed[c][i]) } }
      end
      frame = @glue.apply(frame)
      level(frame)
    end

    # The final stage, after the tape: the true-peak limiter.
    def limit(frame) = @limiter.process(frame)

    # The delay of the limiter in samples.
    def latency = @limiter.latency

    # Whole signals are brought to the target at once; a stream creeps toward it, a little every
    # block, from what it has heard so far.
    def level(frame)
      @meter.feed(frame)
      loud = @meter.integrated
      return clip(frame) unless loud.finite?

      want = (@target - loud).clamp(-15.0, 15.0)
      if @whole
        @gain_db = want
      else
        step = frame.first.size.to_f / SAMPLE_RATE * 2.0 # up to 2 dB a second
        @gain_db += (want - @gain_db).clamp(-step, step)
      end
      gain = Mastering.db(@gain_db)
      clip(frame.map { |channel| channel.map { |v| v * gain } })
    end

    private

    def clip(frame) = frame.map { |channel| channel.map { |v| Colour.soft_limit(v) } }
  end

  # ------------------------------------------------------------------- dither
  # TPDF dither of one least significant bit, from a seeded stream, for export to sixteen bits.
  class Dither
    def initialize(seed, bits = 16)
      @rng = Random.new(seed)
      @lsb = 1.0 / (2**(bits - 1))
    end

    def process(frame) = frame.map { |channel| channel.map { |v| v + ((@rng.rand - @rng.rand) * @lsb) } }
  end

  # ------------------------------------------------------------------- report
  # What was made: integrated loudness, true peak, crest factor, and how alike the channels are.
  def self.report(frame)
    mono = Stereo.fold(frame)
    peak = frame.map { |channel| channel.map(&:abs).max }.max
    rms = Math.sqrt(mono.sum { |x| x * x } / mono.size)
    correlation =
      if frame.size == 2
        l, r = frame
        num = l.each_index.sum { |i| l[i] * r[i] }
        den = Math.sqrt(l.sum { |x| x * x } * r.sum { |x| x * x })
        den.zero? ? 1.0 : num / den
      else
        1.0
      end
    { lufs: Loudness.integrated(frame), true_peak_db: TruePeak.db(frame), crest_db: to_db(peak / [rms, 1e-12].max), correlation: }
  end

  def self.report_line(report)
    format('  loudness: %<lufs>.1f LUFS-I, true peak %<tp>.2f dBTP, crest %<crest>.1f dB, correlation %<corr>.2f',
           lufs: report[:lufs], tp: report[:true_peak_db], crest: report[:crest_db], corr: report[:correlation])
  end
end
