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

# --------------------------------------------------------------------- arp
# A chord's voicing played one note at a time, lowest voice first. Pure ordering: the
# patterns say which voice sounds on which step, the sequencer says when.
module Arp
  # The voices to cycle through: the voicing, repeated an octave up for each extra octave.
  def self.pool(voices, octaves)
    (0...octaves.clamp(1, 2)).flat_map { |o| voices.map { |n| n + 12 * o } }.uniq.sort
  end

  # `count` notes in the named pattern; nil is a rest. random_seeded draws from the seed, so a
  # seed repeats. broken_pairs alternates a low note with one two places up, thumb_pattern
  # returns to the lowest note between the others, pedal_arp holds it on every fourth step,
  # spread_roll plays the voices once, quickly, and leaves them ringing.
  def self.sequence(pattern, pool, count, seed)
    n = pool.size
    case pattern
    when 'up' then Array.new(count) { |k| pool[k % n] }
    when 'down' then Array.new(count) { |k| pool.reverse[k % n] }
    when 'updown' then cycle(pool + pool[1...-1].to_a.reverse, count)
    when 'converge' then cycle((0...n).map { |i| i.even? ? pool[i / 2] : pool[-1 - (i / 2)] }, count)
    when 'broken_pairs' then Array.new(count) { |k| pool[((k / 2) + (k.odd? ? 2 : 0)) % n] }
    when 'thumb_pattern' then Array.new(count) { |k| k.even? ? pool[0] : pool[1 + ((k / 2) % [n - 1, 1].max)] }
    when 'pedal_arp' then Array.new(count) { |k| (k % 4).zero? ? pool[0] : pool[1 + ((k - (k / 4) - 1) % [n - 1, 1].max)] }
    when 'spread_roll' then Array.new(count) { |k| k < n ? pool[k] : nil }
    when 'random_seeded'
      rng = Random.new(seed)
      Array.new(count) { pool[rng.rand(n)] }
    else raise ArgumentError, "no arp pattern #{pattern.inspect}"
    end
  end

  def self.cycle(list, count) = Array.new(count) { |k| list[k % list.size] }
end

# One arpeggio note: `base` is where its step falls on the grid, `off` how far it leans from
# there (swing and humanize, clamped to MAX_OFFSET), the rest as they sound.
Pluck = Struct.new(:base, :off, :midi, :dur, :gain) # midi is one note, or a chord's notes

module Arp
  # The small modifiers that shape the note stream, applied in the order the arp lists them.
  # `slot` is the length of one arp step in seconds; `peak` the strongest accent gain.
  def self.modify(plucks, name, params, rng, slot:, peak:)
    case name
    when 'euclidean'
      steps = params.fetch('steps', 8)
      pulses = params.fetch('pulses', 5).clamp(1, steps)
      plucks.each_with_index.select { |_, i| ((i * pulses) % steps) < pulses }.map(&:first)
    when 'probability'
      plucks.select { |_| rng.rand <= params.fetch('probability', 1.0) }
    when 'note_repeat'
      count = params.fetch('count', 1).clamp(1, 6)
      plucks.flat_map { |p| split(p, count, slot, 0.72, 0.06) }
    when 'ratchet'
      max = params.fetch('max', 3).clamp(1, 4)
      plucks.flat_map do |p|
        accented = p.gain >= peak * 0.99 && rng.rand < params.fetch('chance', 0.5)
        accented && max > 1 ? split(p, rng.rand(2..max), slot, 0.86, 0.11) : [p]
      end
    when 'humanize'
      ms = params.fetch('ms', 4.0) / 1000.0
      g = params.fetch('gain', 0.06)
      plucks.each do |p|
        p.off += rng.rand(-ms..ms)
        p.gain = (p.gain + rng.rand(-g..g)).clamp(0.0, 1.0)
      end
    when 'grace'
      tones = params.fetch('tones', []).sort # a grace note is the next chord tone below, never a chromatic neighbour
      plucks.flat_map do |p|
        below = Array(p.midi).map { |m| tones.reverse.find { |t| t < m } || m }
        grace = Pluck.new(p.base - [p.dur * 0.18, 0.035].max, p.off, p.midi.is_a?(Array) ? below : below.first, [p.dur * 0.12, 0.018].max, p.gain * params.fetch('gain', 0.3))
        [grace, p]
      end
    else raise ArgumentError, "no arp modifier #{name.inspect}"
    end
  end

  # `count` evenly spaced copies of a note within its slot, each `fade` quieter than the last.
  def self.split(pluck, count, slot, held, fade)
    return [pluck] if count <= 1

    each = slot / count
    Array.new(count) do |i|
      Pluck.new(pluck.base + (each * i), pluck.off, pluck.midi, [each * held, 0.018].max, pluck.gain * (1.0 - (fade * i)))
    end
  end
end

