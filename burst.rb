# frozen_string_literal: true

class Burst
  def initialize(density: 30)
    @density = density
  end

  def compute_vectors(intensity)
    Array.new(@density) { { x: rand(-1.0..1.0) * intensity, y: rand(-1.0..1.0) * intensity, r: rand(1..4) } }
  end
end
