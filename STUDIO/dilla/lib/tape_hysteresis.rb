# frozen_string_literal: true

# Jiles-Atherton tape hysteresis, plus Ornstein-Uhlenbeck wow and flutter.
#
# Why this exists when the engine already has saturation. Everything else here
# is memoryless: asoftclip, alimiter, a waveshaper -- output is a function of
# the current sample alone, so the same input value always gives the same output
# value and the transfer curve is a single line. Real tape is not like that. The
# magnetisation of the medium depends on its history, so the curve is a LOOP:
# the output at a given input differs depending on whether the signal is rising
# or falling into it. That path-dependence is why tape compresses a transient
# differently from a sustained tone, and it is the part a waveshaper cannot
# reach however carefully its curve is drawn.
#
# The model is Jiles-Atherton, solved with RK4, which is the standard treatment
# for ferromagnetic hysteresis and what open tape emulations use.
#
# Wow and flutter use an Ornstein-Uhlenbeck process rather than summed sines. A
# capstan does not wander freely and it does not follow a fixed cycle -- it
# drifts and is pulled back toward centre. O-U is exactly that: a random walk
# with a restoring force. Summed sines never repeat either, but they are
# deterministic underneath, and the ear eventually finds the pattern.
module TapeHysteresis
  module_function

  # Langevin function, the anhysteretic magnetisation curve. Series expansion
  # near zero: coth(x) - 1/x is 0/0 there and loses all precision in floating
  # point well before it reaches it.
  def langevin(x)
    return x / 3.0 if x.abs < 1e-4

    (1.0 / Math.tanh(x)) - (1.0 / x)
  end

  def langevin_prime(x)
    return 1.0 / 3.0 if x.abs < 1e-4

    s = Math.sinh(x)
    (1.0 / (x * x)) - (1.0 / (s * s))
  end

  # dM/dH at one point. `delta` carries the direction of travel, and it is the
  # only reason this differs from a memoryless curve.
  def dmdh(m, h, dh, p)
    q = (h + (p[:alpha] * m)) / p[:a]
    m_an = p[:ms] * langevin(q)
    dm = m_an - m
    delta = dh.negative? ? -1.0 : 1.0
    # Guard the denominator: at a turning point dm approaches zero along with
    # the drive, and the quotient is 0/0.
    denom = (p[:k] * delta) - (p[:alpha] * dm)
    denom = (p[:k] * delta) if denom.abs < 1e-9
    irr = dm / denom
    rev = (p[:ms] / p[:a]) * langevin_prime(q)
    ((1.0 - p[:c]) * irr) + (p[:c] * rev)
  end

  DEFAULTS = { ms: 1.0, a: 0.22, alpha: 1.6e-3, k: 0.47, c: 1.7e-1 }.freeze

  # RK4 over the input as the driving field.
  def process(samples, drive: 1.0, params: DEFAULTS)
    m = 0.0
    prev_h = 0.0
    out = Array.new(samples.length)
    samples.each_with_index do |s, i|
      h = s * drive
      dh = h - prev_h
      k1 = dmdh(m, prev_h, dh, params)
      k2 = dmdh(m + (0.5 * k1 * dh), prev_h + (0.5 * dh), dh, params)
      k3 = dmdh(m + (0.5 * k2 * dh), prev_h + (0.5 * dh), dh, params)
      k4 = dmdh(m + (k3 * dh), h, dh, params)
      m += (dh / 6.0) * (k1 + (2.0 * k2) + (2.0 * k3) + k4)
      out[i] = m
      prev_h = h
    end
    out
  end

  # Ornstein-Uhlenbeck: dx = theta*(0 - x)*dt + sigma*dW. theta is how hard it
  # is pulled back, sigma how far it wanders. Seeded, because a flutter you
  # cannot reproduce is not a character.
  def ou_series(length, rate:, theta: 0.55, sigma: 0.9, seed: 7)
    rng = Random.new(seed)
    dt = 1.0 / rate
    x = 0.0
    sqrt_dt = Math.sqrt(dt)
    Array.new(length) do
      # Box-Muller for a normal deviate; rand alone is uniform and gives the
      # walk the wrong distribution of step sizes.
      u1 = [rng.rand, 1e-12].max
      u2 = rng.rand
      g = Math.sqrt(-2.0 * Math.log(u1)) * Math.cos(2.0 * Math::PI * u2)
      x += (-theta * x * dt) + (sigma * sqrt_dt * g)
      x
    end
  end

  # Fractional-delay read, linear interpolation. depth_ms is the peak excursion.
  def apply_wow(samples, rate:, depth_ms: 1.2, seed: 7)
    return samples if depth_ms <= 0.0

    ctrl = ou_series(samples.length, rate:, seed:)
    peak = ctrl.map(&:abs).max
    return samples if peak.zero?

    scale = (depth_ms / 1000.0 * rate) / peak
    max_delay = (depth_ms / 1000.0 * rate).ceil + 2
    out = Array.new(samples.length, 0.0)
    samples.each_index do |i|
      pos = i - max_delay + (ctrl[i] * scale)
      j = pos.floor
      next if j <= 0 || j + 1 >= samples.length

      frac = pos - j
      out[i] = (samples[j] * (1.0 - frac)) + (samples[j + 1] * frac)
    end
    out
  end
end
