# ------------------------------------------------------------- colour chains
# Sonitex and nasty_vcs, as chains rather than plugins. Sonitex is the 12-bit sampler
# lineage: a drive into a hard band limit, bit and rate reduction, a little hiss and dust,
# a compressor and a limiter. One instance is a colour and three are a sound. nasty_vcs is a
# summing colour, applied wherever things are added, which is what a console does and why
# summed material glues. Both are off unless asked for, and then they only colour.
module Colour
  def self.db(x) = 10.0**(x / 20.0)

  def self.highpass(buf, cutoff) = Stream::Highpass.new(cutoff).process(buf)

  # A feed-forward compressor: the level follows the signal, over the threshold the gain falls.
  def self.compress(buf, threshold, ratio, attack_ms, release_ms, makeup) = Stream::Compressor.new(threshold, ratio, attack_ms, release_ms, makeup).process(buf)

  # Sample-rate reduction by `factor` (hold each value) and rounding to `bits` of resolution.
  def self.crush(buf, bits, factor) = Stream::Crush.new(bits, factor).process(buf)

  # Samples under 0.7 pass untouched; above it the level bends toward 1 and never reaches it,
  # so a loud kick stays loud instead of pulling the whole mix down.
  def self.soft_limit(v)
    a = v.abs
    return v if a <= 0.7

    (0.7 + (0.3 * Math.tanh((a - 0.7) / 0.3))) * (v.negative? ? -1 : 1)
  end

  # The passes share one random stream, one after another over the whole signal; the streamed
  # render gives each its own so that blocks of a signal cannot change the draws.
  def self.sonitex(buf, preset, instances, seed)
    rng = Random.new(seed)
    instances.clamp(1, 3).times.inject(buf) { |out, _| Stream::Sonitex.new(preset, rng).process(out) }
  end

  # A heavy but static tape stage for drum buses: input bandwidth, a restrained head bump,
  # saturation and compression. No wow, flutter, tremolo, chorus or other pitch modulation.
  def self.tape(buf, amount: 1.0)
    amount = amount.to_f.clamp(0.0, 1.0)
    return buf if amount.zero? || buf.empty?

    pre = FX.lowpass(buf, 14_000.0)
    low = FX.lowpass(pre, 82.0)
    drive = 1.0 + (3.2 * amount)
    wet_share = 0.72 * amount
    curve = Math.tanh(drive)
    out = pre.each_index.map do |i|
      pushed = pre[i] + (low[i] * 0.10 * amount)
      saturated = Math.tanh(pushed * drive) / curve
      (pre[i] * (1.0 - wet_share)) + (saturated * wet_share)
    end
    out = highpass(out, 26.0)
    compress(out, -15.0, 2.8, 7.0, 85.0, 0.0)
  end

  # The summing colour: a soft knee that bends only the peaks, a touch of low warmth, and
  # unity gain for small signals, so summed material glues without getting louder.
  def self.vcs(buf, amount) = amount.to_f <= 0.0 ? buf : Stream::Vcs.new(amount).process(buf)
end

