# frozen_string_literal: true

module Master
  # One deterministic seam for stochastic tools. Callers may supply their own
  # RNG; these helpers cover the places that genuinely need process-local draws.
  module Random
    module_function

    def rng(seed = nil) = seed.nil? ? ::Random.new : ::Random.new(seed)
    def integer(max, seed: nil) = rng(seed).rand(Integer(max))
    def float(seed: nil) = rng(seed).rand
  end
end
