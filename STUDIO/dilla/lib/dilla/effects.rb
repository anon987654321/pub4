# ---------------------------------------------------------------------- FX
module FX
  def self.lowpass(buf, cutoff)
    return buf if cutoff.nil?
    rc = 1.0 / (2 * Math::PI * cutoff)
    dt = 1.0 / SAMPLE_RATE
    a  = dt / (rc + dt)
    y  = 0.0
    buf.map { |x| y += a * (x - y); y }
  end

  def self.reverb(buf, amount)
    return buf if amount.nil? || amount <= 0
    delays = [0.0297, 0.0371, 0.0411, 0.0437].map { |d| (d * SAMPLE_RATE).to_i }
    gains  = [0.70, 0.65, 0.60, 0.55]
    out = buf.dup
    delays.each_with_index do |d, k|
      i = d
      while i < out.size
        out[i] += out[i - d] * gains[k] * amount
        i += 1
      end
    end
    peak = out.map(&:abs).max
    peak > 1.0 ? out.map { |s| s / peak } : out
  end

  # A dub send built on the existing multi-head echo: saturated, band-limited repeats
  # with feedback, but deliberately no reverb or time-varying modulation.
  def self.dub_echo(buf, settings)
    return buf unless settings

    Echo.process(
      buf,
      delay: settings.fetch('delay_ms').to_f / 1000.0,
      heads: settings.fetch('heads', [1, 2, 3]),
      intensity: settings.fetch('intensity', 0.6),
      volume: settings.fetch('volume', 0.6),
      lowpass: settings.fetch('lowpass', 4800),
      saturation: settings.fetch('saturation', 0.8),
      reverb: settings.fetch('reverb', 0.0),
      tail: settings.fetch('tail', 1.0),
      resets: []
    )
  end

  # A crystallizer-style pitch-shifted delay. Short, Hann-windowed grains overlap to shift
  # the pitch by a fixed interval. Feedback moves each later repeat up another interval;
  # no LFO, vibrato, chorus or reverb is used.
  def self.crystallizer(buf, settings)
    return buf unless settings
    return buf if buf.empty?

    delay = settings.fetch('delay_ms', 350).to_f.clamp(20.0, 2000.0) / 1000.0
    semitones = settings.fetch('semitones', 12).to_f.clamp(-24.0, 24.0)
    feedback = settings.fetch('feedback', 0.35).to_f.clamp(0.0, 0.85)
    mix = settings.fetch('mix', 0.35).to_f.clamp(0.0, 1.0)
    repeats = settings.fetch('repeats', 3).to_i.clamp(1, 8)
    tail = settings.fetch('tail', 1.0).to_f.clamp(0.0, 5.0)
    grain = [(settings.fetch('grain_ms', 80).to_f.clamp(20.0, 200.0) * SAMPLE_RATE / 1000.0).round, 32].max
    delay_samples = [(delay * SAMPLE_RATE).round, 1].max
    extra = [(tail * SAMPLE_RATE).round, delay_samples * repeats].max
    out = Array.new(buf.size + extra, 0.0)
    buf.each_with_index { |sample, i| out[i] = sample }
    ratio = 2.0**(semitones / 12.0)
    shifted = crystal_shift(buf, ratio, grain)

    repeats.times do |repeat|
      start = delay_samples * (repeat + 1)
      gain = mix * (feedback**repeat)
      shifted.each_with_index do |sample, i|
        index = start + i
        break if index >= out.size

        out[index] += sample * gain
      end
      shifted = crystal_shift(shifted, ratio, grain) if repeat + 1 < repeats
    end
    out
  end

  def self.crystal_shift(buf, ratio, grain)
    return buf.dup if buf.empty?

    hop = [grain / 2, 1].max
    window = Array.new(grain) do |j|
      0.5 - (0.5 * Math.cos(2.0 * Math::PI * j / [grain - 1, 1].max))
    end
    source_offsets = Array.new(grain) { |j| (j * ratio).floor % grain }
    out = Array.new(buf.size, 0.0)
    weights = Array.new(buf.size, 0.0)
    (0...buf.size).step(hop) do |base|
      grain.times do |j|
        target = base + j
        break if target >= buf.size

        source = base + source_offsets[j]
        next if source >= buf.size

        weight = window[j]
        out[target] += buf[source] * weight
        weights[target] += weight
      end
    end
    out.each_index { |i| out[i] /= weights[i] if weights[i] > 1e-9 }
    out
  end

  # The profile's texture: lowpass, then reverb.
  def self.apply(buf, profile)
    t = profile['texture'] || {}
    reverb(lowpass(buf, t['lowpass']), t['reverb'])
  end
end
