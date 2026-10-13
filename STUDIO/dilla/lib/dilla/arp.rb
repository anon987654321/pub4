# frozen_string_literal: true

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
    when 'spiral' then cycle(spiral(n).map { |i| pool[i] }, count)
    when 'pendulum' then cycle(pendulum(n).map { |i| pool[i] }, count)
    when 'fibonacci' then cycle(fibonacci(n, 64).map { |i| pool[i] }, count)
    when 'prime_walk' then cycle(prime_walk(n).map { |i| pool[i] }, count)
    when 'call_response' then Array.new(count) { |k| call_response(pool, k) }
    when 'pedal_point' then Array.new(count) { |k| k.even? ? pool[0] : pool[1 + (((k / 2)) % [n - 1, 1].max)] }
    when 'random_seeded'
      rng = Random.new(seed)
      Array.new(count) { pool[rng.rand(n)] }
    else raise ArgumentError, "no arp pattern #{pattern.inspect}"
    end
  end

  def self.cycle(list, count) = Array.new(count) { |k| list[k % list.size] }

  # From the middle outward, one either side in turn, and back in again.
  def self.spiral(n)
    centre = n / 2
    out = [centre] + (1...n).flat_map { |d| [centre + d, centre - d] }.select { |i| i.between?(0, n - 1) }
    out + out[1...-1].to_a.reverse
  end

  # Up two, back one, to the top, and the same down again.
  def self.pendulum(n)
    up = [0]
    i = 0
    while i < n - 1
      up << [i + 2, n - 1].min
      up << i + 1
      i += 1
    end
    up + up[1...-1].to_a.reverse
  end

  # The Fibonacci numbers taken round the pool: 1, 1, 2, 3, 5, 8, ... modulo its size.
  def self.fibonacci(n, count)
    a, b = 1, 1
    Array.new(count) { a.tap { a, b = b, a + b } % n }
  end

  # Strides of the first primes round the pool, so the walk takes a long time to come back.
  def self.prime_walk(n)
    primes = [2, 3, 5, 7, 11, 13]
    i = 0
    Array.new(primes.size * 4) { |k| (i = (i + primes[k % primes.size]) % n) }
  end

  # Four notes rising, then three falling from higher up, then a rest.
  def self.call_response(pool, k)
    n = pool.size
    case k % 8
    when 0..3 then pool[(k % 8) % n]
    when 4..6 then pool[[n - 1, 4].min - ((k % 8) - 4) % n]
    end
  end
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

