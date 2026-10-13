# ------------------------------------------------------------- colour chains
# Sonitex and nasty_vcs, as chains rather than plugins. Sonitex is the 12-bit sampler
# lineage: a drive into a hard band limit, bit and rate reduction, a little hiss and dust,
# a compressor and a limiter. One instance is a colour and three are a sound. nasty_vcs is a
# summing colour, applied wherever things are added, which is what a console does and why
# summed material glues. Both are off unless asked for, and then they only colour.
module Colour
  def self.db(x) = 10.0**(x / 20.0)

  def self.highpass(buf, cutoff)
    a = 1.0 / (1.0 + (2 * Math::PI * cutoff / SAMPLE_RATE))
    y = prev = 0.0
    buf.map do |x|
      y = a * (y + x - prev)
      prev = x
      y
    end
  end

  # A feed-forward compressor: the level follows the signal, over the threshold the gain falls.
  def self.compress(buf, threshold, ratio, attack_ms, release_ms, makeup)
    up = 1.0 - Math.exp(-1.0 / (attack_ms / 1000.0 * SAMPLE_RATE))
    down = 1.0 - Math.exp(-1.0 / (release_ms / 1000.0 * SAMPLE_RATE))
    limit = db(threshold)
    gain_up = db(makeup)
    level = 0.0
    buf.map do |x|
      a = x.abs
      level += (a > level ? up : down) * (a - level)
      over = level > limit ? (limit / level)**(1.0 - (1.0 / ratio)) : 1.0
      x * over * gain_up
    end
  end

  # Sample-rate reduction by `factor` (hold each value) and rounding to `bits` of resolution.
  def self.crush(buf, bits, factor)
    levels = 2.0**(bits - 1)
    held = 0.0
    clock = factor
    buf.map do |x|
      if clock >= factor
        held = (x * levels).round / levels
        clock -= factor
      end
      clock += 1.0
      held
    end
  end

  # Samples under 0.7 pass untouched; above it the level bends toward 1 and never reaches it,
  # so a loud kick stays loud instead of pulling the whole mix down.
  def self.soft_limit(v)
    a = v.abs
    return v if a <= 0.7

    (0.7 + (0.3 * Math.tanh((a - 0.7) / 0.3))) * (v.negative? ? -1 : 1)
  end

  # One pass of the chain with one preset's numbers (see dilla.json).
  def self.sonitex_pass(buf, p, rng)
    drive = p.fetch('dist_drive')
    mix = p.fetch('dist_mix')
    dc = p.fetch('dist_dc')
    pre = FX.lowpass(buf, p.fetch('dist_pre_lp'))
    out = buf.each_index.map do |i|
      wet = Math.tanh((pre[i] * drive) + dc) - Math.tanh(dc)
      (buf[i] * (1.0 - mix)) + (wet * mix / [drive, 1.0].max * 1.2)
    end
    bump = db(p.fetch('head_bump_db')) - 1.0
    low = FX.lowpass(out, p.fetch('head_bump_hz'))
    out = out.each_index.map { |i| out[i] + (bump * low[i]) }
    crushed = FX.lowpass(crush(out, p.fetch('crush_bits'), p.fetch('crush_sr')), p.fetch('crush_post_lp'))
    cm = p.fetch('crush_mix')
    out = out.each_index.map { |i| (out[i] * (1.0 - cm)) + (crushed[i] * cm) }
    out = FX.lowpass(FX.lowpass(out, p.fetch('hf_rolloff')), p.fetch('hf_rolloff'))
    out = highpass(out, p.fetch('lf_rolloff'))
    hiss = p.fetch('hiss_amp')
    pops = p.fetch('pop_rate')
    pop = 0.0
    pop_amp = p.fetch('pop_amp')
    out = out.map do |x|
      pop = (rng.rand < pops ? (rng.rand < 0.5 ? -pop_amp : pop_amp) : pop) * 0.985
      x + (((rng.rand * 2) - 1) * hiss) + (pop * 0.4)
    end
    out = compress(out, p.fetch('out_comp_threshold'), p.fetch('out_comp_ratio'), 12.0, 120.0, p.fetch('out_comp_makeup') - 1.0)
    lim = p.fetch('limit')
    level = p.fetch('level_out')
    out.map { |x| lim * Math.tanh(x / lim) * level }
  end

  def self.sonitex(buf, preset, instances, seed)
    rng = Random.new(seed)
    out = buf
    instances.clamp(1, 3).times { out = sonitex_pass(out, preset, rng) }
    out
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
  def self.vcs(buf, amount)
    return buf if amount.to_f <= 0.0

    amount = amount.clamp(0.0, 1.0)
    drive = 1.0 + (2.0 * amount)
    warm = FX.lowpass(buf, 180.0)
    buf.each_index.map do |i|
      (Math.tanh((buf[i] + (0.12 * amount * warm[i])) * drive) / drive)
    end
  end
end

