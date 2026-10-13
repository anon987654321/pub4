# frozen_string_literal: true

# --------------------------------------------------------------------- kits
# Drum voices synthesised in plain Ruby, each a row of dilla.json. A kit maps the roles a
# pattern uses (kick, snare, clap, hat, open, rim, tom, perc) to voices with their tunings.
# Every voice is built once per render from a seed, so a seed names a kit as it names a take,
# and is scaled to a peak, so the mix levels in the data are the only loudness knob.
module Percussion
  TAU = 2 * Math::PI
  PEAKS = { 'kick' => 0.9, 'snare' => 0.7, 'clap' => 0.7, 'hat' => 0.3, 'open' => 0.3, 'rim' => 0.5, 'tom' => 0.7, 'perc' => 0.5 }.freeze

  def self.n(seconds) = (seconds * SAMPLE_RATE).to_i

  def self.lowpass(buf, hz)
    k = 1.0 - Math.exp(-TAU * hz / SAMPLE_RATE)
    y = 0.0
    buf.map { |x| y += k * (x - y) }
  end

  def self.highpass(buf, hz)
    k = 1.0 - Math.exp(-TAU * hz / SAMPLE_RATE)
    low = 0.0
    buf.map { |x| low += k * (x - low); x - low }
  end

  def self.bandpass(buf, lo, hi) = lowpass(highpass(buf, lo), hi)

  def self.noise(rng, count) = Array.new(count) { (rng.rand * 2) - 1 }

  def self.mix(*bufs)
    Array.new(bufs.map(&:size).max) { |i| bufs.sum { |b| b[i] || 0.0 } }
  end

  def self.scale_to(buf, peak)
    top = buf.map(&:abs).max
    top.to_f.zero? ? buf : buf.map { |x| x * peak / top }
  end

  # Drive into tanh, level-matched by the curve's own ceiling, and a fold past 0.6 for the
  # hardest settings: harmonics generated rather than borrowed from volume.
  def self.dirt(buf, amount)
    return buf if amount <= 0.0

    drive = 1.0 + (amount * 6.0)
    ceiling = Math.tanh(drive)
    out = buf.map { |x| Math.tanh(x * drive) / ceiling }
    return out if amount <= 0.6

    fold = 1.2 + amount
    out.map { |x| x + ((amount - 0.6) * Math.sin(x * fold * Math::PI)) * 0.5 }
  end

  # Short noise, highpassed: the beater.
  def self.click(rng, ms, hz = 1800.0) = highpass(noise(rng, [n(ms / 1000.0), 1].max), hz)

  # A sine whose pitch falls exponentially from body+sweep to body, a decaying amplitude, a click.
  def self.techno_kick(spec, rng, scale = 1.0)
    length = n(0.5 * scale)
    phase = 0.0
    body = Array.new(length) do |i|
      t = i.to_f / SAMPLE_RATE
      phase += TAU * (spec['body'] + (spec['sweep'] * Math.exp(-t * spec['sweep_decay']))) / SAMPLE_RATE
      Math.sin(phase) * Math.exp(-t * spec['amp_decay'] / scale)
    end
    body = dirt(body, spec['drive'])
    click = click(rng, spec['click_ms']).map { |x| x * 0.5 }
    mix(click, body)
  end

  def self.fm_kick(_spec, _rng)
    raw = Array.new(n(0.5)) do |i|
      t = i.to_f / SAMPLE_RATE
      (0.85 * Math.exp(-6 * t) * Math.sin((TAU * 55 * t) + (6 * Math.exp(-30 * t) * Math.sin(TAU * 58 * t)))) +
        (0.35 * Math.exp(-9 * t) * Math.sin(TAU * 42 * t))
    end
    lowpass(raw.map { |x| Math.tanh(1.8 * x) }, 240.0)
  end

  def self.fm_pair(carrier, modulator, index, decay, length, index_decay = 30.0)
    Array.new(n(length)) do |i|
      t = i.to_f / SAMPLE_RATE
      Math.sin((TAU * carrier * t) + (index * Math.exp(-t * index_decay) * Math.sin(TAU * modulator * t))) * Math.exp(-t * decay)
    end
  end

  def self.fm_snare(_spec, rng)
    body = fm_pair(200, 330, 7, 18, 0.25)
    crack = highpass(noise(rng, n(0.25)), 1500.0).each_with_index.map { |x, i| x * Math.exp(-25.0 * i / SAMPLE_RATE) }
    mix(body, crack.map { |x| x * 0.6 })
  end

  def self.fm_hat(spec, _rng)
    highpass(fm_pair(spec.fetch('carrier', 900), spec.fetch('modulator', 3150), 5, spec.fetch('decay', 90), 0.12, 20.0), 4000.0)
  end

  def self.kick_808(_spec, rng)
    phase = 0.0
    body = Array.new(n(1.6)) do |i|
      t = i.to_f / SAMPLE_RATE
      phase += TAU * (43 + (67 * Math.exp(-26 * t))) / SAMPLE_RATE
      Math.sin(phase) * Math.exp(-t * 3.0)
    end
    mix(body, click(rng, 8, 1800.0).map { |x| x * 0.3 })
  end

  # A short, layered boom: a sub that falls fast, a click, and a body near 150 Hz.
  def self.boom_808(_spec, rng)
    sub_phase = 0.0
    sub = Array.new(n(0.6)) do |i|
      t = i.to_f / SAMPLE_RATE
      sub_phase += TAU * (42 + (108 * Math.exp(-55 * t))) / SAMPLE_RATE
      Math.sin(sub_phase) * Math.exp(-t * 4.5)
    end
    body = Array.new(n(0.2)) { |i| t = i.to_f / SAMPLE_RATE; Math.sin(TAU * 150 * t) * Math.exp(-t * 20) * 0.4 }
    mix(sub, body, click(rng, 9, 1800.0).map { |x| x * 0.3 })
  end

  # Six detuned square oscillators at metallic ratios, crushed to 12 bits, highpassed.
  def self.hat_909(spec, rng)
    freqs = [205.3, 304.4, 369.6, 522.7, 540.0, 800.0]
    length = n(spec['open'] ? 0.4 : 0.07)
    decay = spec['open'] ? 7.0 : 45.0
    raw = Array.new(length) do |i|
      t = i.to_f / SAMPLE_RATE
      freqs.each_with_index.sum { |f, k| (((t * f * (1.0 + (0.01 * (k - 2)))) % 1.0) < 0.5 ? 1.0 : -1.0) } / 6.0 * Math.exp(-t * decay)
    end
    levels = 2.0**11
    crushed = raw.map { |x| (x * levels).round / levels }
    highpass(crushed, spec.fetch('highpass', 7000.0)).map { |x| x + ((rng.rand * 2 - 1) * 0.0) }
  end

  # Four short noise bursts a few milliseconds apart, bandpassed, then a longer room tail.
  def self.clap_909(_spec, rng)
    out = Array.new(n(0.28), 0.0)
    [[0.0, 1750], [0.017, 1650], [0.036, 1500], [0.058, 1400]].each_with_index do |(at, fc), k|
      burst = bandpass(noise(rng, n(0.012)), fc * 0.6, fc * 1.5)
      burst.each_with_index { |x, i| out[n(at) + i] += x * Math.exp(-i * 400.0 / SAMPLE_RATE) * (k == 3 ? 0.8 : 0.9) if n(at) + i < out.size }
    end
    tail = bandpass(noise(rng, out.size), 800.0, 1150.0).each_with_index.map { |x, i| x * Math.exp(-i * 22.0 / SAMPLE_RATE) * 0.5 }
    start = n(0.058)
    tail.each_with_index { |x, i| out[start + i] += x if start + i < out.size }
    out
  end

  # Two detuned bodies and highpassed noise with a snappy envelope.
  def self.snare_909(spec, rng)
    tone = Array.new(n(0.2)) do |i|
      t = i.to_f / SAMPLE_RATE
      ((Math.sin(TAU * spec.fetch('body', 185) * t) + (0.8 * Math.sin(TAU * spec.fetch('body', 185) * 1.78 * t))) * Math.exp(-t * 22))
    end
    snap = highpass(noise(rng, n(0.2)), 1800.0).each_with_index.map { |x, i| x * Math.exp(-i * 18.0 / SAMPLE_RATE) }
    mix(tone.map { |x| x * 0.5 }, snap)
  end

  def self.rim(_spec, rng)
    modes = [1.0, 2.61, 4.19]
    ring = Array.new(n(0.06)) do |i|
      t = i.to_f / SAMPLE_RATE
      modes.each_with_index.sum { |m, k| Math.sin(TAU * 430 * m * t) / (k + 1.0) } * Math.exp(-t * 90)
    end
    mix(ring, click(rng, 3, 2600.0))
  end

  def self.tom(spec, _rng)
    phase = 0.0
    Array.new(n(0.35)) do |i|
      t = i.to_f / SAMPLE_RATE
      phase += TAU * (spec.fetch('to', 90) + ((spec.fetch('from', 160) - spec.fetch('to', 90)) * Math.exp(-t * 14))) / SAMPLE_RATE
      Math.sin(phase) * Math.exp(-t * 9)
    end
  end

  # Decaying inharmonic partials plus a bandpassed noise strike. modes are [ratio, decay].
  def self.modal(spec, rng)
    hz = spec.fetch('hz')
    length = n(spec.fetch('length', 0.4))
    bend = spec.fetch('bend', 0.0)
    ring = Array.new(length) do |i|
      t = i.to_f / SAMPLE_RATE
      spec.fetch('modes').sum { |ratio, decay| Math.sin(TAU * hz * ratio * (1.0 + (bend * Math.exp(-t * 30))) * t) * Math.exp(-t * decay) }
    end
    strike = bandpass(noise(rng, n(0.01)), hz * 0.5, hz * 3.0).map { |x| x * 0.4 }
    mix(ring, strike)
  end

  def self.shaker(spec, rng)
    highpass(noise(rng, n(spec.fetch('length', 0.07))), 6000.0).each_with_index.map { |x, i| x * Math.exp(-i * 50.0 / SAMPLE_RATE) }
  end

  # Struck sheet metal: five decaying modes, rung hard and driven.
  def self.metal(_spec, rng)
    modes = [[211, 9], [568, 16], [903, 24], [1371, 38], [1836, 52]]
    strike = click(rng, 6, 1500.0)
    Array.new(n(0.5)) do |i|
      t = i.to_f / SAMPLE_RATE
      ring = modes.sum { |hz, d| Math.sin(TAU * hz * t) * Math.exp(-t * (d / 8.0)) } / 3.0
      Math.tanh(2.6 * ((1.9 * ring) + (strike[i] || 0.0)))
    end
  end

  # The samples for one kit voice.
  def self.voice(spec, data, rng)
    raw =
      case spec.fetch('voice')
      when 'techno_kick' then techno_kick(data.fetch('kick_styles').fetch(spec.fetch('style')), rng, spec.fetch('tail', 1.0))
      when 'fm_kick' then fm_kick(spec, rng)
      when 'fm_snare' then fm_snare(spec, rng)
      when 'fm_hat' then fm_hat(spec, rng)
      when 'kick_808' then kick_808(spec, rng)
      when 'boom_808' then boom_808(spec, rng)
      when 'hat_909' then hat_909(spec, rng)
      when 'clap_909' then clap_909(spec, rng)
      when 'snare_909' then snare_909(spec, rng)
      when 'rim' then rim(spec, rng)
      when 'tom' then tom(spec, rng)
      when 'modal' then modal(data.fetch('modal_patches').fetch(spec.fetch('patch')).merge(spec), rng)
      when 'shaker' then shaker(spec, rng)
      when 'metal' then metal(spec, rng)
      else raise ArgumentError, "no kit voice #{spec['voice'].inspect}"
      end
    raw = lowpass(raw, spec['lowpass']) if spec['lowpass']
    scale_to(raw, spec.fetch('peak', PEAKS.fetch(spec.fetch('role', 'perc'), 0.5)))
  end

  # A kit's voices by role. The seed gives each role its own noise.
  def self.kit(name, data, seed)
    data.fetch('kits').fetch(name) { abort "No kit: #{name}" }.each_with_object({}) do |(role, spec), out|
      next unless spec.is_a?(Hash) && spec.key?('voice')

      out[role] = voice(spec.merge('role' => role), data, Random.new(Zlib.crc32("#{seed}:#{role}")))
    end
  end

  # The low end grown from the kicks themselves: a long room, a lowpass, drive, two more lowpasses.
  def self.rumble(kick_bus)
    tail = lowpass(FX.reverb(kick_bus, 0.8), 180.0)
    tail = lowpass(lowpass(dirt(tail, 0.55), 110.0), 110.0)
    scale_to(tail, 0.6)
  end
end
