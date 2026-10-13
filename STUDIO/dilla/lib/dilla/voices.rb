# ------------------------------------------------------------------ voices
# Every voice turns a note (a frequency, a length and a level) into samples. The sine voice
# above is the plain one; these are the others, each described by a row of dilla.json.
# Nothing here resamples: a note is synthesised at its own pitch, and a fundamental above
# NYQUIST_SHARE of the sample rate is dropped, never folded back down.
module Voices
  TAU = 2 * Math::PI

  def self.audible?(freq) = freq.positive? && freq <= SAMPLE_RATE * NYQUIST_SHARE

  # A held level 0..1 for an [attack, decay, sustain, release] envelope, linear segments.
  def self.adsr(env, t, gate)
    a, d, s, r = env
    level = lambda do |x|
      if x < a then x / [a, 1e-4].max
      elsif x < a + d then 1.0 - ((1.0 - s) * (x - a) / [d, 1e-4].max)
      else s
      end
    end
    return level.call(t) if t <= gate

    [level.call(gate) * (1.0 - ((t - gate) / [r, 1e-4].max)), 0.0].max
  end

  WAVES = {
    'saw' => ->(p) { (2.0 * p) - 1.0 },
    'pulse' => ->(p) { p < 0.5 ? 1.0 : -1.0 },
    'triangle' => ->(p) { p < 0.5 ? (4.0 * p) - 1.0 : 3.0 - (4.0 * p) },
    'sine' => ->(p) { Math.sin(TAU * p) }
  }.freeze

  # A four-pole ladder lowpass: each pole moves toward the one before, the last feeds back.
  # The pole coefficient is x / (1 + x), which needs no exponential in the sample loop.
  class Ladder
    def initialize
      @z = [0.0, 0.0, 0.0, 0.0]
    end

    def process(sample, cutoff, resonance)
      x = TAU * cutoff.clamp(20.0, SAMPLE_RATE * 0.45) / SAMPLE_RATE
      g = x / (1.0 + x)
      input = sample - (resonance * 4.0 * @z[3])
      input /= (1.0 + (input.abs * 0.5)) # soft limit on the way in, so the resonance rounds off
      @z[0] += g * (input - @z[0])
      @z[1] += g * (@z[0] - @z[1])
      @z[2] += g * (@z[1] - @z[2])
      @z[3] += g * (@z[2] - @z[3])
    end
  end

  # Detuned saw and pulse oscillators on phase accumulators, a ladder with its own envelope
  # sweeping the cutoff, and an amplitude envelope. Detune is in cents, octaves are integers.
  def self.moog(patch, freq, dur, amp)
    return [] unless audible?(freq)

    amp_env = patch.fetch('amp')
    filter_env = patch.fetch('filter_env')
    base = patch.fetch('cutoff')
    sweep = patch.fetch('env_amount')
    resonance = patch.fetch('resonance')
    n = ((dur + amp_env[3]) * SAMPLE_RATE).to_i
    waves = patch.fetch('waves').map { |w| WAVES.fetch(w) }
    incs = patch.fetch('waves').each_index.map do |k|
      freq * (2.0**(patch.fetch('octaves')[k] + (patch.fetch('detune')[k] / 1200.0))) / SAMPLE_RATE
    end
    phases = Array.new(waves.size) { |k| k * 0.13 }
    ladder = Ladder.new
    drive = patch.fetch('drive', 1.0)
    scale = amp * 2.0 / waves.size
    Array.new(n) do |i|
      t = i.to_f / SAMPLE_RATE
      sum = 0.0
      waves.each_index do |k|
        sum += waves[k].call(phases[k])
        phases[k] = (phases[k] + incs[k]) % 1.0
      end
      ladder.process(sum * drive * 0.5, base + (sweep * adsr(filter_env, t, dur)), resonance) * adsr(amp_env, t, dur) * scale
    end
  end

  # An electric piano by frequency modulation: a body pair near 1:1 for the mellow tine, a
  # bell pair at 14:1 whose index falls away in a few tenths of a second, a soft hammer click,
  # and a velocity that brightens it. No tremolo and no chorus: nothing moves but the decay.
  def self.rhodes(patch, freq, dur, amp, velocity)
    return [] unless audible?(freq)

    release = patch.fetch('release')
    n = ((dur + release) * SAMPLE_RATE).to_i
    bright = 0.5 + (patch.fetch('velocity_bright') * velocity)
    body = patch.fetch('body_index') * bright
    bell = patch.fetch('bell_index') * bright
    bell_ratio = patch.fetch('bell_ratio')
    bell_k = Math.exp(-1.0 / (patch.fetch('bell_decay') * SAMPLE_RATE))
    body_k = Math.exp(-1.0 / (patch.fetch('body_decay') * SAMPLE_RATE))
    amp_k = Math.exp(-1.0 / (patch.fetch('decay') * SAMPLE_RATE))
    click_k = Math.exp(-1.0 / (0.003 * SAMPLE_RATE))
    rng = Random.new(freq.to_i)
    out_k = Math.exp(-1.0 / (release * SAMPLE_RATE / 4.0))
    carrier = modulator = bell_c = bell_m = 0.0
    body_env = bell_env = amp_env = click_env = hold = 1.0
    cinc = freq / SAMPLE_RATE
    gate_n = (dur * SAMPLE_RATE).to_i
    Array.new(n) do |i|
      m = Math.sin(TAU * modulator)
      b = Math.sin(TAU * bell_m)
      s = Math.sin(TAU * (carrier + (body * body_env * m / TAU))) * 0.8
      s += Math.sin(TAU * (bell_c + (bell * bell_env * b / TAU))) * 0.12 * bell_env
      s += ((rng.rand * 2) - 1) * click_env * patch.fetch('click')
      carrier = (carrier + cinc) % 1.0
      modulator = (modulator + cinc) % 1.0
      bell_c = (bell_c + cinc) % 1.0
      bell_m = (bell_m + (cinc * bell_ratio)) % 1.0
      body_env *= body_k
      bell_env *= bell_k
      click_env *= click_k
      amp_env *= amp_k
      hold *= out_k if i >= gate_n
      s * amp_env * hold * amp * 1.4
    end
  end

  # One hit of a drum-synth voice: a triangle oscillator frequency-modulates a square, both
  # fall in pitch, noise is mixed in, a ladder lowpass and the amplifier each decay. The
  # exponentials are running products, one multiply a sample.
  def self.dfam(patch, freq, dur, amp, decay)
    return [] unless audible?(freq)

    n = [(decay * 4 * SAMPLE_RATE).to_i, (dur * SAMPLE_RATE).to_i].max
    env = patch.fetch('pitch_env')
    pe_k = Math.exp(-1.0 / (env.fetch('seconds') * SAMPLE_RATE))
    ve_k = Math.exp(-1.0 / (decay * SAMPLE_RATE))
    fe_k = Math.exp(-1.0 / (patch.fetch('vcf_decay') * SAMPLE_RATE))
    mix = patch.fetch('mix')
    rng = Random.new(freq.to_i)
    ladder = Ladder.new
    p1 = p2 = 0.0
    pe = ve = fe = 1.0
    Array.new(n) do
      f1 = freq * (1.0 + (env.fetch('depth') * pe))
      tri = WAVES['triangle'].call(p1)
      f2 = f1 * patch.fetch('vco2_ratio') * (1.0 + (patch.fetch('fm') * tri))
      sq = p2 < 0.5 ? 1.0 : -1.0
      p1 = (p1 + (f1 / SAMPLE_RATE)) % 1.0
      p2 = (p2 + (f2 / SAMPLE_RATE)) % 1.0
      src = (tri * mix.fetch('triangle')) + (sq * mix.fetch('square')) + (((rng.rand * 2) - 1) * mix.fetch('noise'))
      cutoff = patch.fetch('cutoff_floor') + (patch.fetch('cutoff') * fe)
      out = ladder.process(src, cutoff, patch.fetch('resonance')) * ve * amp * 2.0
      pe *= pe_k
      ve *= ve_k
      fe *= fe_k
      out
    end
  end

  # A bank of sine partials on a pattern gate, the bubbling organ of dub. The gate is a row of
  # steps, each one cell long, switched by the grid and not by an oscillator: a cell is `x` for
  # open and anything else for shut, and a one-pole slew of a few milliseconds keeps the
  # edges from clicking. `step` is a sixteenth of the tempo in seconds.
  def self.gated(patch, freq, dur, amp, step)
    return [] unless audible?(freq)

    envelope = patch.fetch('amp')
    pattern = patch.fetch('pattern')
    cell = (step || 0.125) * patch.fetch('cell_steps', 1)
    slew = 1.0 - Math.exp(-1.0 / (patch.fetch('slew', 0.004) * SAMPLE_RATE))
    parts = patch.fetch('partials').filter_map { |ratio, weight| [freq * ratio / SAMPLE_RATE, weight] if audible?(freq * ratio) }
    phases = Array.new(parts.size, 0.0)
    total = parts.sum { |_, weight| weight }
    n = ((dur + envelope[3]) * SAMPLE_RATE).to_i
    open = 0.0
    Array.new(n) do |i|
      t = i.to_f / SAMPLE_RATE
      open += slew * ((pattern[(t / cell).floor % pattern.size] == 'x' ? 1.0 : 0.0) - open)
      sum = 0.0
      parts.each_index do |k|
        sum += parts[k][1] * Math.sin(TAU * phases[k])
        phases[k] = (phases[k] + parts[k][0]) % 1.0
      end
      sum / total * open * adsr(envelope, t, dur) * amp
    end
  end

  # A pipe organ by addition: one sine for each rank of the registration, at the rank's ratio to
  # the played pitch (sixteen foot 0.5, eight foot 1, four foot 2, two and two thirds 3, two 4,
  # the mixture's ranks 6 and 8), and a chiff of about fifteen milliseconds, a burst of noise
  # that dies away as the pipe speaks. Nothing moves afterwards: there is no tremulant. The
  # `registration` is a row of weights for the ratios, else the voice's first.
  def self.organ(patch, freq, dur, amp, registration)
    return [] unless audible?(freq)

    ratios = patch.fetch('ratios')
    weights = registration || patch.fetch('registrations').values.first
    ranks = ratios.each_index.filter_map { |k| [freq * ratios[k] / SAMPLE_RATE, weights[k]] if weights[k].to_f.positive? && audible?(freq * ratios[k]) }
    envelope = patch.fetch('amp')
    total = ranks.sum { |_, weight| weight }
    phases = Array.new(ranks.size, 0.0)
    n = ((dur + envelope[3]) * SAMPLE_RATE).to_i
    chiff = patch.fetch('chiff')
    chiff_k = Math.exp(-1.0 / (chiff.fetch('seconds') * SAMPLE_RATE / 3.0))
    chiff_env = chiff.fetch('level')
    rng = Random.new(freq.to_i)
    soft = 0.0
    Array.new(n) do |i|
      t = i.to_f / SAMPLE_RATE
      sum = 0.0
      ranks.each_index do |k|
        sum += ranks[k][1] * Math.sin(TAU * phases[k])
        phases[k] = (phases[k] + ranks[k][0]) % 1.0
      end
      soft += 0.35 * (((rng.rand * 2) - 1) - soft)
      sample = ((sum / total) + (soft * chiff_env)) * adsr(envelope, t, dur) * amp
      chiff_env *= chiff_k
      sample
    end
  end

  # The samples for one note of the named voice. `decay` is the drum voice's own, per step;
  # `step` is a sixteenth of the tempo in seconds and `registration` the organ's weights.
  def self.note(spec, midi, dur, amp, velocity: 1.0, detune: 0.0, decay: nil, step: nil, registration: nil)
    freq = Chords.hz(midi)
    amp *= 10.0**(spec.fetch('gain', 0.0) / 20.0)
    case spec.fetch('family')
    when 'pure' then Synth.pure_note(freq, dur, amp:, release: spec.fetch('release', 0.12), attack: spec.fetch('attack', 0.008))
    when 'sine' then audible?(freq) ? Synth.note(freq, dur, detune:, amp:, release: dur * 0.5) : []
    when 'moog' then moog(spec, freq, dur, amp)
    when 'rhodes' then rhodes(spec, freq, dur, amp, velocity)
    when 'dfam' then dfam(spec, freq, dur, amp, decay || spec.fetch('decay', 0.12))
    when 'gated' then gated(spec, freq, dur, amp, step)
    when 'organ' then organ(spec, freq, dur, amp, registration)
    when 'fluid' then raise ArgumentError, "voice #{spec['name'].inspect} is a soundfont voice: the sequencer mixes it, a single note cannot"
    else raise ArgumentError, "no voice family #{spec['family'].inspect}"
    end
  end
end

