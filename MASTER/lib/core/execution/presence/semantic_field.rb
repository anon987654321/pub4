# frozen_string_literal: true

module Master
  module Core
    module Execution
      module Presence
        # The Semantic Field translates abstract meaning into universal dimensions.
        # This avoids "animation" logic in favor of "state" projection.
        class SemanticField
          DIMENSIONS = %i[
            attention   # 0.0 (idle) to 1.0 (hyper-focused)
            energy      # 0.0 (stagnant) to 1.0 (high activity)
            coherence    # 0.0 (fractured/error) to 1.0 (stable/verified)
            density      # 0.0 (dispersed) to 1.0 (clustered)
            complexity   # 0.0 (simple/point) to 1.0 (complex/topology)
            direction    # :inward, :outward, :stable, :shifting
            uncertainty  # 0.0 (certain) to 1.0 (confused)
            risk         # 0.0 (safe) to 1.0 (critical)
            progress     # 0.0 to 1.0
            scale        # :compact, :medium, :cinematic
          ].freeze

          def self.derive(phase, target = nil, progress: 0.0, risk: 0.0)
            {
              attention: phase == :idle ? 0.2 : 0.8,
              energy: energy_for(phase),
              coherence: coherence_for(phase, risk),
              density: density_for(phase, target),
              complexity: complexity_for(phase, target),
              direction: direction_for(phase),
              uncertainty: uncertainty_for(phase),
              risk:,
              progress:,
              scale: :medium, # Default, can be overridden by client profile,
            }
          end

          private

          def self.energy_for(phase)
            {
              idle: 0.1, listening: 0.3, understanding: 0.5,
              researching: 0.7, discovering: 0.8, reasoning: 0.6,
              executing: 0.9, validate: 0.7, error: 0.4, success: 0.2,
            }[phase] || 0.2
          end

          def self.coherence_for(phase, risk)
            return 0.2 if phase == :error
            return 1.0 if phase == :success
            1.0 - (risk * 0.5)
          end

          def self.density_for(phase, target)
            return 0.9 if target # Clustered around target
            {
              idle: 0.3, listening: 0.5, understanding: 0.9,
              researching: 0.4, discovering: 0.7, reasoning: 0.6,
              executing: 0.8, validate: 0.9,
            }[phase] || 0.5
          end

          def self.complexity_for(phase, target)
            return 0.8 if target
            {
              idle: 0.1, listening: 0.2, understanding: 0.4,
              researching: 0.7, discovering: 0.6, reasoning: 0.8,
              executing: 0.5, validate: 0.7,
            }[phase] || 0.3
          end

          def self.direction_for(phase)
            {
              listening: :inward, understanding: :inward, researching: :shifting,
              discovering: :outward, reasoning: :shifting, executing: :outward,
              validate: :stable, error: :shifting, success: :stable,
            }[phase] || :stable
          end

          def self.uncertainty_for(phase)
            {
              idle: 0.0, listening: 0.2, understanding: 0.4,
              researching: 0.6, discovering: 0.3, reasoning: 0.5,
              executing: 0.2, validate: 0.3, error: 0.8, success: 0.0,
            }[phase] || 0.2
          end
        end
      end
    end
  end
end
