# frozen_string_literal: true

module Master
  module Core
    module Presence
      # The ParticleField transforms the system's semantic state into a 
      # visual nervous system. Every particle has a reason to exist.
      class ParticleField
        # Species define the physics and visual role of particles.
        SPECIES = {
          core: { physics: :stable, color: :identity, role: :presence },
          flow: { physics: :streaming, color: :activity, role: :work },
          spark: { physics: :discrete, color: :event, role: :success },
          cloud: { physics: :diffuse, color: :uncertainty, role: :exploration },
          scar: { physics: :static, color: :error, role: :unresolved }
        }.freeze

        def initialize(container)
          @container = container
        end

        # Projects the current Presence::State and Event Spine into particle behaviors.
        def project(presence_state, current_event = nil)
          {
            energy_level: calculate_energy(presence_state),
            topology: derive_topology(presence_state),
            active_species: derive_species(presence_state, current_event),
            metrics: {
              coherence: presence_state.field[:coherence],
              dispersion: 1.0 - presence_state.field[:density],
              tension: presence_state.field[:risk]
            }
          }
        end

        private

        def calculate_energy(state)
          # Energy is a function of activity and risk.
          # Idle = low energy, Executing = high energy.
          base = state.activity || 0.2
          risk_multiplier = 1.0 + (state.risk || 0.0)
          (base * risk_multiplier).clamp(0.0, 1.0)
        end

        def derive_topology(state)
          # Maps semantic field to structural organization.
          # uncertainty -> wide dispersion, confidence -> tight coherence.
          return :fractured if state.field[:coherence] < 0.3
          return :crystalline if state.field[:coherence] > 0.9
          
          state.field[:direction] == :inward ? :converging : :exploring
        end

        def derive_species(state, event)
          species = [:core]
          
          # Flow particles appear during active work
          species << :flow if state.phase != :idle
          
          # Spark particles on discrete events
          species << :spark if event && event[:type] == :success
          
          # Cloud particles during uncertainty or discovery
          species << :cloud if state.field[:uncertainty] > 0.6
          
          # Scars remain for unresolved errors
          species << :scar if state.severity == :critical
          
          species.uniq
        end
      end
    end
  end
end
