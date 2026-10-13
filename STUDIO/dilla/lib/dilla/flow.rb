# frozen_string_literal: true

# -------------------------------------------------------------------- flow
# A fluid arpeggio. A random walk called energy, 0 to 1, drifts from beat to beat along an arch
# over each chord, and everything that makes an arpeggio busy follows it: the rate breathes
# from quarters through eighths and triplets to sixteenths, rests thin out, the velocity
# rises, and the octave span opens. The order of the notes is a seeded Markov chain over the
# chord's tones that prefers to move by a step and to keep its direction. A run swells toward
# its top note and the notes passed on the way are ghosted. The phrase leans a little inside the
# clamp, early in the body of a chord and late at its end. Every note is a tone of the chord.
module Flow
  # Energy up to which each rate holds, in sixteenths a note: a quarter, an eighth, a triplet
  # eighth (three to the beat), a sixteenth.
  RATES = [[0.25, 4.0], [0.5, 2.0], [0.75, 4.0 / 3.0], [1.01, 1.0]].freeze

  def self.rate(energy) = RATES.find { |limit, _| energy < limit }.last

  # The energy walk: small seeded steps pulled toward a target, held inside 0..1.
  class Walk
    attr_reader :value

    def initialize(seed, start: 0.5)
      @rng = Random.new(seed)
      @value = start
    end

    def step(target)
      @value = (@value + ((@rng.rand - 0.5) * 0.36) + (0.18 * (target - @value))).clamp(0.02, 0.98)
    end
  end

  # One chord of the arpeggio. Returns [plucks, energies], the energies one for each beat, for
  # the swell of a pad beneath.
  def self.chord_events(voices, index:, chord_steps:, step:, seed:, walk:, settings:, gate: 0.8)
    rng = Random.new(Zlib.crc32("#{seed}:flow:#{index}"))
    beats = (chord_steps / 4.0).ceil
    arch = ->(beat) { 0.25 + (0.6 * Math.sin(Math::PI * (beat + 0.5) / beats)) }
    energies = []
    picks = []
    pos = 0.0
    last = nil
    direction = 1
    beat = -1
    energy = walk.value
    while pos < chord_steps - 1e-6
      if (pos / 4).floor > beat
        beat = (pos / 4).floor
        energy = walk.step(arch.call(beat))
        energies << energy
      end
      pool = Arp.pool(voices, energy > 0.55 ? 2 : 1)
      length = rate(energy)
      rest = !picks.empty? && rng.rand < (1.0 - energy) * 0.3
      unless rest
        near = last && pool.each_index.min_by { |j| (pool[j] - last).abs } # the pool grows and shrinks with the energy; the note held in mind does not
        i = next_index(pool, near, direction, rng)
        direction = i <=> near if near && i != near
        last = pool[i]
        picks << [pos, pool[i], energy, i, pool.size]
      end
      pos += length
    end
    [pluck_stream(picks, index, chord_steps, step, gate, settings), energies.empty? ? [walk.value] : energies]
  end

  # The next index into the pool: near the last, away from standing still, keeping the way it was going.
  def self.next_index(pool, last, direction, rng)
    return rng.rand(pool.size) if last.nil? || last >= pool.size

    weights = pool.each_index.map do |j|
      pull = Math.exp(-(j - last).abs / 1.3)
      pull *= 0.25 if j == last
      pull *= 1.6 if j != last && (j <=> last) == direction
      pull
    end
    roll = rng.rand * weights.sum
    weights.each_with_index { |w, j| return j if (roll -= w).negative? }
    pool.size - 1
  end

  # Plucks from the picks: velocity from the energy and the height in the pool, the notes between a
  # lower and a higher neighbour ghosted, and the lean of the phrase.
  def self.pluck_stream(picks, index, chord_steps, step, gate, settings)
    accent = settings.fetch('flow_ghost', 0.45)
    picks.each_with_index.map do |(pos, midi, energy, i, size), k|
      before = k.positive? ? picks[k - 1][3] : nil
      after = picks[k + 1]&.fetch(3)
      passing = before && after && ((before < i && i < after) || (before > i && i > after))
      height = size > 1 ? i.to_f / (size - 1) : 0.5
      gain = (0.4 + (0.55 * energy)) * (0.75 + (0.25 * height)) * (passing ? accent : 1.0)
      until_next = (picks[k + 1]&.first || chord_steps) - pos
      u = pos / chord_steps
      lean = ((-0.4 * 0.02 * Math.sin(Math::PI * u)) + (u > 0.8 ? 0.02 * (((u - 0.8) / 0.2)**2) : 0.0)).clamp(-MAX_OFFSET, MAX_OFFSET)
      Pluck.new(((index * chord_steps) + pos) * step, lean, midi, until_next * step * gate, gain.clamp(0.05, 1.0))
    end
  end

  # A pad that swells with the energy: linear between the beats' levels, from a quarter to full.
  def self.swell(pad, energies, beat_samples)
    return pad if energies.empty?

    pad.each_with_index.map do |v, i|
      pos = i.to_f / beat_samples
      a = energies[[pos.floor, energies.size - 1].min]
      b = energies[[pos.floor + 1, energies.size - 1].min]
      v * (0.25 + (0.75 * (a + ((b - a) * (pos - pos.floor)))))
    end
  end
end
