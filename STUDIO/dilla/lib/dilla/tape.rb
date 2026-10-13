# frozen_string_literal: true

# ------------------------------------------------------------------- tape
# The last colour before the file. One instance is a tape machine reduced to what is static in
# it: a Jiles-Atherton hysteresis loop for the medium (the output depends on whether the signal
# is rising or falling into a level, which a waveshaper cannot reproduce), a head bump near fifty
# hertz and the loss at the top. Nothing moves: no wow, no flutter, no hiss. Further instances
# use an arctangent curve in place of the loop, which costs a fraction of it, and each is level
# matched against its own measurement of a reference signal, so a stack changes colour and not
# loudness. Every stage keeps its state between calls, so a signal cut into chunks leaves the
# stack exactly as one long call does.
module Tape
  TAU = 2 * Math::PI
  REFERENCE_TONES = [110.0, 440.0, 1760.0].freeze # whole cycles in 0.2 s: Goertzel bins land exactly

  # Amplitude of one frequency in a signal, by the Goertzel recurrence.
  def self.goertzel(samples, freq)
    coeff = 2.0 * Math.cos(TAU * freq / SAMPLE_RATE)
    s1 = s2 = 0.0
    samples.each do |x|
      s0 = x + (coeff * s1) - s2
      s2 = s1
      s1 = s0
    end
    power = (s1 * s1) + (s2 * s2) - (coeff * s1 * s2)
    2.0 * Math.sqrt([power, 0.0].max) / samples.size
  end

  def self.rms(samples) = samples.empty? ? 0.0 : Math.sqrt(samples.sum { |x| x * x } / samples.size)

  def self.db(ratio) = 20.0 * Math.log10([ratio, 1e-12].max)

  # A second-order section in transposed direct form II (the RBJ cookbook shapes).
  class Biquad
    def self.peaking(hz, q, gain_db)
      a = 10.0**(gain_db / 40.0)
      w = TAU * hz / SAMPLE_RATE
      alpha = Math.sin(w) / (2.0 * q)
      cos = Math.cos(w)
      new([1 + (alpha * a), -2 * cos, 1 - (alpha * a)], [1 + (alpha / a), -2 * cos, 1 - (alpha / a)])
    end

    def self.lowpass(hz, q = Math.sqrt(0.5))
      w = TAU * hz / SAMPLE_RATE
      alpha = Math.sin(w) / (2.0 * q)
      cos = Math.cos(w)
      new([(1 - cos) / 2, 1 - cos, (1 - cos) / 2], [1 + alpha, -2 * cos, 1 - alpha])
    end

    def self.highpass(hz, q = Math.sqrt(0.5))
      w = TAU * hz / SAMPLE_RATE
      alpha = Math.sin(w) / (2.0 * q)
      cos = Math.cos(w)
      new([(1 + cos) / 2, -(1 + cos), (1 + cos) / 2], [1 + alpha, -2 * cos, 1 - alpha])
    end

    def initialize(b, a)
      @b0 = b[0] / a[0]
      @b1 = b[1] / a[0]
      @b2 = b[2] / a[0]
      @a1 = a[1] / a[0]
      @a2 = a[2] / a[0]
      @z1 = @z2 = 0.0
    end

    def step(x)
      y = (@b0 * x) + @z1
      @z1 = (@b1 * x) - (@a1 * y) + @z2
      @z2 = (@b2 * x) - (@a2 * y)
      y
    end

    def reset
      @z1 = @z2 = 0.0
    end

    def process(buf) = buf.map { |x| step(x) }
  end

  # The magnetisation of the medium as the signal drives it. Ms is the saturation level, a the
  # shape of the anhysteretic curve, alpha the coupling between domains, k the width of the
  # loop and c the share that bends back without loss. Solved with Runge-Kutta over each sample.
  class Hysteresis
    DEFAULTS = { 'ms' => 1.0, 'a' => 0.22, 'alpha' => 1.6e-3, 'k' => 0.47, 'c' => 0.17 }.freeze

    def initialize(params = {})
      p = DEFAULTS.merge(params)
      @ms = p['ms'].to_f
      @a = p['a'].to_f
      @alpha = p['alpha'].to_f
      @k = p['k'].to_f
      @c = p['c'].to_f
      @m = 0.0
      @h = 0.0
    end

# dM/dH at one point; the sign of dh is the direction of travel. The Langevin function and
# its slope share one exponential: coth(x) - 1/x and 1/x^2 - 1/sinh(x)^2, which near zero
# lose all their digits and are taken from their series instead.
def slope(m, h, dh)
  q = (h + (@alpha * m)) / @a
  if q.abs < 1e-4
    langevin = q / 3.0
    prime = 1.0 / 3.0
  else
    q = q.clamp(-40.0, 40.0)
    e = Math.exp(q)
    inv = 1.0 / e
    sinh2 = e - inv
    langevin = ((e + inv) / sinh2) - (1.0 / q)
    prime = (1.0 / (q * q)) - (4.0 / (sinh2 * sinh2))
  end
  dm = (@ms * langevin) - m
  reach = dh.negative? ? -@k : @k
  denom = reach - (@alpha * dm)
  denom = reach if denom.abs < 1e-9
  ((1.0 - @c) * (dm / denom)) + (@c * (@ms / @a) * prime)
end

    def step(field)
      dh = field - @h
      k1 = slope(@m, @h, dh)
      k2 = slope(@m + (0.5 * k1 * dh), @h + (0.5 * dh), dh)
      k3 = slope(@m + (0.5 * k2 * dh), @h + (0.5 * dh), dh)
      k4 = slope(@m + (k3 * dh), field, dh)
      @m += (dh / 6.0) * (k1 + (2.0 * k2) + (2.0 * k3) + k4)
      @h = field
      @m
    end
  end

  # One machine: the medium, then the playback head's bump and the loss at the top.
  class Machine
    attr_reader :makeup

    # `curve` is :loop for the hysteresis model or :atan for the cheap curve; `reference` is the
    # RMS of the signal the makeup gain is measured at.
    def initialize(drive:, curve:, config:, rng:, reference:, sample: nil)
      @drive = drive
      @curve = curve
      jitter = ->(share) { 1.0 + (share * ((rng.rand * 2) - 1)) } # each instance is a slightly different machine
      loop_params = (config['hysteresis'] || {}).dup
      loop_params['k'] = loop_params.fetch('k', Hysteresis::DEFAULTS['k']) * jitter.call(0.04)
      @params = loop_params
      @field = curve == :loop ? config.fetch('field_scale', 0.4) : config.fetch('cheap_field', 1.2)
      @bump = Biquad.peaking(config.fetch('bump_hz', 50.0) * jitter.call(0.06), config.fetch('bump_q', 1.1), config.fetch('bump_db', 1.5))
      @top = Biquad.lowpass(config.fetch('hf_hz', 16_500.0) * jitter.call(0.03))
      @block = Biquad.highpass(config.fetch('block_hz', 18.0))
      @loop = Hysteresis.new(@params) if curve == :loop
      @makeup = 1.0
      @makeup = sample ? calibrate_on(sample) : calibrate(reference)
      reset
    end

    def reset
      @loop = Hysteresis.new(@params) if @curve == :loop
      [@bump, @top, @block].each(&:reset)
    end

    def process(buf)
      gain = @drive * @field
      if @curve == :loop
        buf.map { |x| @block.step(@top.step(@bump.step(@loop.step(x * gain)))) * @makeup }
      else
        norm = 1.0 / gain
        buf.map { |x| @block.step(@top.step(@bump.step(Math.atan(x * gain) * norm))) * @makeup }
      end
    end

    private

    # Gain that returns a stretch of the programme itself to its own RMS, measured after the
    # loop has settled. The tones below suit a stack with no programme to hand.
    def calibrate_on(sample)
      settle = (0.1 * SAMPLE_RATE).round
      heard = Tape.rms(process(sample).drop(settle))
      reset
      heard.positive? ? Tape.rms(sample.drop(settle)) / heard : 1.0
    end

    # Gain that returns a reference signal (three tones at the given RMS) to its own level,
    # measured by Goertzel on the fundamentals after the loop has settled.
    def calibrate(reference)
      amp = reference * Math.sqrt(2.0 / REFERENCE_TONES.size)
      total = (0.3 * SAMPLE_RATE).round
      signal = Array.new(total) { |i| REFERENCE_TONES.sum { |f| amp * Math.sin(TAU * f * i / SAMPLE_RATE) } }
      out = process(signal).last((0.2 * SAMPLE_RATE).round)
      heard = Math.sqrt(REFERENCE_TONES.sum { |f| Tape.goertzel(out, f)**2 })
      reset
      heard.positive? ? (amp * Math.sqrt(REFERENCE_TONES.size)) / heard : 1.0
    end
  end

  # N machines in series, the first with the loop and the rest on the cheap curve, each driven a
  # step harder than the one before.
  class Stack
    attr_reader :machines

    # `sample` is a stretch of the programme to level match against; without one the stack is
    # matched on three reference tones at `config['reference']` RMS.
    def initialize(instances:, drive: 1.0, seed: 0, config: {}, sample: nil)
      heard = sample
      @machines = Array.new(instances) do |i|
        step = 1.0 + (config.fetch('drive_step', 0.15) * i)
        machine = Machine.new(drive: drive * step, curve: i.zero? ? :loop : :atan, config:, sample: heard,
                              rng: Random.new(Zlib.crc32("#{seed}:tape:#{i}")), reference: config.fetch('reference', 0.12))
        heard = machine.process(heard) if heard
        machine.reset
        machine
      end
    end

    def process(buf) = @machines.reduce(buf) { |signal, machine| machine.process(signal) }
  end

  # A soft ceiling, the last thing the signal meets: below the knee nothing changes, above it
  # the level bends toward the ceiling and never reaches it.
  def self.ceiling(buf, knee: 0.8, top: 0.97)
    room = top - knee
    buf.map do |v|
      a = v.abs
      a <= knee ? v : (knee + (room * Math.tanh((a - knee) / room))) * (v.negative? ? -1.0 : 1.0)
    end
  end

  # Up to three stretches of the programme, from its start, middle and end, for the level match.
  def self.excerpt(buf, seconds: 0.8)
    len = (seconds * SAMPLE_RATE).round
    return buf if buf.size <= len * 3

    [0, (buf.size - len) / 2, buf.size - len].flat_map { |from| buf[from, len] }
  end

  # The whole stage on a finished signal. Zero instances is the signal itself, untouched.
  def self.apply(buf, instances:, drive: 1.0, seed: 0, config: {})
    return buf if instances.to_i <= 0 || buf.empty?

    ceiling(Stack.new(instances: instances.to_i, drive:, seed:, config:, sample: excerpt(buf)).process(buf),
            top: config.fetch('ceiling', 0.97))
  end
end
