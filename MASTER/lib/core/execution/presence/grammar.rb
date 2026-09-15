# frozen_string_literal: true

module Master
  module Core
    module Execution
      module Presence
        # Grammar maps execution states and semantic targets to visual behaviors.
        # This is the "dictionary" the generative face uses to morph its topology.
        class Grammar
          # Visual behaviors for execution phases.
          PHASE_GRAMMAR = {
            idle: {
              topology: :organic_swarm,
              motion: :breathing,
              color_profile: :ambient
            },
            listening: {
              topology: :oriented_swarm,
              motion: :attracted,
              color_profile: :receptive
            },
            understanding: {
              topology: :converging_point,
              motion: :imploding,
              color_profile: :focused
            },
            researching: {
              topology: :branching_tree,
              motion: :exploratory,
              color_profile: :active
            },
            discovering: {
              topology: :illuminated_nodes,
              motion: :pulsing,
              color_profile: :highlight
            },
            reasoning: {
              topology: :reorganizing_mesh,
              motion: :shifting,
              color_profile: :intellectual
            },
            executing: {
              topology: :directional_flow,
              motion: :streaming,
              color_profile: :operational
            },
            validate: {
              topology: :coherent_structure,
              motion: :solidifying,
              color_profile: :critical
            },
            error: {
              topology: :fractured_swarm,
              motion: :propagating_shock,
              color_profile: :warning
            },
            success: {
              topology: :stable_crystalline,
              motion: :settling,
              color_profile: :resolved
            }
          }.freeze

          # Visual grammars for semantic targets (what MASTER is attending to).
          TARGET_GRAMMAR = {
            code: { topology: :branching_filesystem, motion: :cascading },
            data: { topology: :node_network, motion: :interconnecting },
            music: { topology: :waveform_oscillation, motion: :vibrating },
            person: { topology: :bilateral_figure, motion: :attending },
            city: { topology: :dense_glowing_grid, motion: :urban_flow },
            relationship: { topology: :linked_entities, motion: :tethered },
            abstract_concept: { topology: :geometric_emergence, motion: :evolving },
            error: { topology: :disturbance_cluster, motion: :erratic }
          }.freeze

          def self.for_phase(phase)
            PHASE_GRAMMAR[phase] || PHASE_GRAMMAR[:idle]
          end

          def self.for_target(target)
            TARGET_GRAMMAR[target] || { topology: :organic_swarm, motion: :idle }
          end
        end
      end
    end
  end
end
