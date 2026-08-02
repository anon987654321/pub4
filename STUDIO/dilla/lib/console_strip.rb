# frozen_string_literal: true

# A console channel strip, applied per channel rather than across the mix.
#
# The engine already has analog processing -- sonitex tape filters, an analog
# emulation chain, bus_analog_filter, Jiles-Atherton hysteresis. All of it runs
# on the master or on a bus, which is the one place a real console does NOT put
# its character. On a desk every channel passes its own preamp and its own
# transformer first, and the sound people mean by "console" is the SUM of thirty
# of those, each slightly different from the next because no two are built to
# the same tolerance. One instance on the master is a different effect: it is
# the same curve applied to everything at once, after the summing that was
# supposed to accumulate the differences.
#
# Two things follow, and they are the whole design:
#
# 1. EVEN harmonics, not odd. A symmetric curve -- plain tanh, asoftclip, any
#    odd-symmetric shaper -- can only produce odd harmonics: 3rd, 5th, 7th. The
#    3rd is a twelfth, musically dissonant against the fundamental, and it is
#    what makes cheap saturation read as harsh or edgy. The 2nd harmonic is an
#    OCTAVE, consonant by definition, and it is what "warm" and "soothing"
#    actually describe. Getting it requires an ASYMMETRIC curve, because a
#    symmetric one cancels every even term exactly. Transformers and tubes are
#    asymmetric; that is why they sound the way they do and why a symmetric
#    digital clipper never gets there however it is tuned.
#
# 2. Per-instance variation. Each strip draws its own drive, bias, headroom and
#    HF corner from a seeded RNG, so channels differ from one another the way
#    real ones do. Seeded rather than random: a console whose character changes
#    every render is not a character, and it also makes any A/B meaningless.
#
# The sub is deliberately excluded from the saturation. Harmonics generated from
# a 50 Hz fundamental land at 100 and 150 Hz, directly in the range that has
# repeatedly been this mix's problem, and they arrive as ADDED energy the
# metering does not attribute to the kick. Saturating only above the crossover
# is why this can be pushed for warmth without the low end thickening.
module ConsoleStrip
  module_function

  # Asymmetric transfer curve. The bias is the entire reason this generates even
  # harmonics: it moves the signal off the symmetric point of the curve, so the
  # positive and negative halves are compressed by different amounts. The DC the
  # offset introduces is subtracted back out -- tanh(drive*bias) is exactly the
  # curve's output at silence, and leaving it in would put a step in the signal.
  def shape(x, drive, bias)
    Math.tanh(drive * (x + bias)) - Math.tanh(drive * bias)
  end

  # One-pole coefficient for a given corner frequency.
  def pole(hz, rate)
    return 1.0 if hz >= rate / 2.0

    c = 1.0 - Math.exp(-2.0 * Math::PI * hz / rate)
    c.clamp(0.0, 1.0)
  end

  # Split at the crossover, saturate only the upper band, recombine.
  #
  # Complementary first-order: the low band is a one-pole lowpass and the high
  # band is whatever is left (x - low), so the two sum back to flat by
  # construction. A pair of independent filters would not -- they would sum with
  # a dip or a bump at the crossover, and the strip would colour the response
  # before any saturation happened.
  def saturate_band(samples, rate:, xover_hz: 120.0, drive: 1.6, bias: 0.08, hf_hz: 12_000.0)
    a = pole(xover_hz, rate)
    h = pole(hf_hz, rate)
    low = 0.0
    hf = 0.0
    norm = shape(1.0, drive, bias).abs
    norm = 1.0 if norm < 1e-9
    samples.map do |x|
      low += a * (x - low)
      high = x - low
      # Transformer HF loss: real iron does not pass the top octave intact, and
      # the gentle rolloff is a large part of why the result reads as soothing
      # rather than merely distorted.
      hf += h * (high - hf)
      low + (shape(hf, drive, bias) / norm)
    end
  end

  # Gentle level-dependent gain, the strip's own compressor.
  #
  # A soft knee and a low ratio: this exists to take the edge off transients on
  # the way in, not to control dynamics. Anything heavier belongs on the bus,
  # and stacking a real compressor on every channel is how a mix loses the
  # loudness range this engine has repeatedly had to claw back.
  def soften(samples, rate:, threshold: 0.35, ratio: 1.6, attack_ms: 12.0, release_ms: 160.0)
    at = Math.exp(-1.0 / ((attack_ms / 1000.0) * rate))
    rt = Math.exp(-1.0 / ((release_ms / 1000.0) * rate))
    env = 0.0
    samples.map do |x|
      level = x.abs
      env = level > env ? (at * env) + ((1.0 - at) * level) : (rt * env) + ((1.0 - rt) * level)
      gain =
        if env <= threshold
          1.0
        else
          over = env - threshold
          (threshold + (over / ratio)) / env
        end
      x * gain
    end
  end

  # Per-instance character. Every channel on a desk is built to the same design
  # and none of them measures the same; these are the tolerances.
  def instance(seed)
    rng = Random.new(seed)
    {
      drive: 1.15 + (rng.rand * 0.45),
      # Bias sets the even-to-odd ratio, and the first values here were chosen by
      # eye at 0.05-0.11, which measurement then showed to be the harsh zone
      # rather than the warm one. Sweeping a 220 Hz sine, 2nd-minus-3rd is:
      #
      #   bias 0.05   -3.5 dB   3rd DOMINATES -- the edge this exists to avoid
      #   bias 0.10   +2.7 dB   marginal
      #   bias 0.18   +8.6 dB   2nd clearly leads
      #   bias 0.28  +14.4 dB   strongly even
      #   bias 0.40  +22.0 dB   even-dominant but heavy
      #
      # So the original defaults produced almost exactly the opposite of the
      # stated intent: at 0.05 the curve is asymmetric enough to be measured and
      # not asymmetric enough to matter, leaving the odd harmonics on top. 0.16
      # to 0.30 is the range where the octave actually leads, and it is the only
      # part of this module that could not have been reasoned to without the
      # measurement.
      #
      # Sign varies per instance: transformers are not all asymmetric in the
      # same direction, and alternating it means the even harmonics of different
      # channels do not all stack in phase into a single audible octave-up.
      bias: (0.16 + (rng.rand * 0.14)) * (rng.rand < 0.5 ? -1.0 : 1.0),
      xover_hz: 105.0 + (rng.rand * 35.0),
      hf_hz: 9_000.0 + (rng.rand * 6_000.0),
      threshold: 0.32 + (rng.rand * 0.10),
    }
  end

  # One channel through one strip.
  def process(samples, rate:, seed: 1, amount: 1.0)
    return samples if amount <= 0.0

    p = instance(seed)
    wet = saturate_band(samples, rate:,
                        xover_hz: p[:xover_hz], drive: p[:drive],
                        bias: p[:bias], hf_hz: p[:hf_hz])
    wet = soften(wet, rate:, threshold: p[:threshold])
    return wet if amount >= 1.0

    samples.each_with_index.map { |x, i| (x * (1.0 - amount)) + (wet[i] * amount) }
  end

  # Harmonic content of a processed signal, for verifying the thing actually
  # does what the comments claim. Goertzel at the fundamental and its multiples,
  # returned in dB relative to the fundamental.
  #
  # This exists because a previous saturation stage in this engine was committed
  # with a description of the harmonics it added and measured, later, as doing
  # nothing at all. A saturator is trivially testable -- feed it a sine, look at
  # what appears above it -- and anything claiming to add harmonics should carry
  # the measurement rather than the adjective.
  def harmonics(samples, rate:, fundamental:, count: 5)
    mags = (1..count).map do |n|
      f = fundamental * n
      next 0.0 if f >= rate / 2.0

      w = 2.0 * Math::PI * f / rate
      coeff = 2.0 * Math.cos(w)
      s1 = 0.0
      s2 = 0.0
      samples.each do |x|
        s0 = x + (coeff * s1) - s2
        s2 = s1
        s1 = s0
      end
      Math.sqrt((s1 * s1) + (s2 * s2) - (coeff * s1 * s2)) / samples.length
    end
    base = mags[0]
    return mags.map { 0.0 } if base <= 1e-12

    mags.map { |m| m <= 1e-12 ? -120.0 : (20.0 * Math.log10(m / base)).round(2) }
  end
end
