# frozen_string_literal: true

# Deterministic, synthesised drum voices. Each hit has a shaped transient, a musical body
# and a noise/metal layer; the seeded generator makes a render repeatable.
class Drums
  def initialize(seed)
    @rng = Random.new(seed)
  end

  def kick(dur = 0.28)
    n = [(dur * SAMPLE_RATE).to_i, 1].max
    phase = 0.0
    Array.new(n) do |i|
      t = i.to_f / SAMPLE_RATE
      envelope = Math.exp(-t * 13.5)
      frequency = 43.0 + 112.0 * Math.exp(-t * 34.0)
      phase += 2.0 * Math::PI * frequency / SAMPLE_RATE
      body = Math.sin(phase) * envelope
      click = (Math.sin(2.0 * Math::PI * 1850.0 * t) * Math.exp(-t * 180.0)) * 0.12
      sub = Math.sin(2.0 * Math::PI * 48.0 * t) * Math.exp(-t * 8.0) * 0.18
      soft_clip((body * 0.82) + click + sub)
    end
  end

  def snare(dur = 0.22)
    n = [(dur * SAMPLE_RATE).to_i, 1].max
    previous = 0.0
    Array.new(n) do |i|
      t = i.to_f / SAMPLE_RATE
      noise = (@rng.rand * 2.0) - 1.0
      high_noise = noise - previous
      previous = noise
      snap = high_noise * Math.exp(-t * 72.0) * 0.34
      wire = noise * Math.exp(-t * 23.0) * 0.36
      body_env = Math.exp(-t * 24.0)
      body = (Math.sin(2.0 * Math::PI * 188.0 * t) * 0.48 +
              Math.sin(2.0 * Math::PI * 312.0 * t) * 0.16) * body_env
      soft_clip(body + wire + snap)
    end
  end

  def hat(dur = 0.075)
    n = [(dur * SAMPLE_RATE).to_i, 1].max
    previous = 0.0
    partials = [401.0, 557.0, 733.0, 997.0, 1321.0, 1709.0]
    phases = partials.map { @rng.rand * 2.0 * Math::PI }
    Array.new(n) do |i|
      t = i.to_f / SAMPLE_RATE
      noise = (@rng.rand * 2.0) - 1.0
      high = noise - previous
      previous = noise
      metal = partials.each_with_index.sum { |f, j| Math.sin(2.0 * Math::PI * f * t + phases[j]) } / partials.size
      envelope = Math.exp(-t * 58.0)
      soft_clip((high * 0.24 + metal * 0.19) * envelope)
    end
  end

  def sounds = { 'kick' => kick, 'snare' => snare, 'hat' => hat }

  private

  def soft_clip(value)
    Math.tanh(value * 1.35) / Math.tanh(1.35)
  end
end
