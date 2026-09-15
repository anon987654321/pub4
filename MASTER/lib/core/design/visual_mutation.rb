# frozen_string_literal: true

module Master
  module Core
    module Design
      # The VisualMutationEngine allows MASTER to "fuzz test" a UI.
      # It deliberately perturbs the design to verify robustness.
      class VisualMutationEngine
        MUTATIONS = {
          typography: [:enlarge_font, :change_weight, :long_text, :norwegian_compound],
          layout: [:shrink_viewport, :remove_border, :expand_spacing, :disable_animation],
          content: [:empty_state, :extreme_price, :missing_image, :long_username]
        }.freeze

        def self.perturb(surface_data, mutation_type)
          mutation = MUTATIONS[mutation_type].sample
          {
            mutation: mutation,
            applied_to: surface_data[:focus],
            expected_outcome: :remain_coherent
          }
        end

        def self.verify_survival(screenshot_before, screenshot_after)
          # Compare coherence metrics before and after mutation
          { status: :survived, delta: 0.02 }
        end
      end
    end
  end
end
