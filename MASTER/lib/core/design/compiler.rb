# frozen_string_literal: true

module Master
  module Core
    module Design
      # The DesignCompiler treats UI as a compilation problem.
      # Intent -> Semantics -> Tokens -> Constraints -> Implementation.
      class Compiler
        def initialize(container)
          @container = container
        end

        # Compiles a high-level design intent into a structured intermediate representation (IR).
        def compile(intent, surface_type: :general)
          {
            surface: surface_type,
            semantics: derive_semantics(intent),
            tokens: map_to_tokens(intent),
            constraints: derive_constraints(intent),
            priority_map: determine_importance(intent)
          }
        end

        private

        def derive_semantics(intent)
          # Extracts the core purpose (e.g., discovery, transaction, communication)
          {
            purpose: intent.include?("search") ? :discovery : :action,
            density: :high,
            platform: :mobile_first
          }
        end

        def map_to_tokens(intent)
          # Maps intent to specific LayoutGrammar tokens
          {
            spacing: :m,
            typography: { title: :card_title, body: :body },
            radius: :subtle
          }
        end

        def derive_constraints(intent)
          # Generates a set of non-negotiable visual constraints
          [
            { property: :touch_target, min: 44 },
            { property: :max_width, value: "65ch" },
            { property: :overflow, value: :none }
          ]
        end

        def determine_importance(intent)
          # Assigns semantic importance scores to elements
          {
            title: :critical,
            price: :primary,
            location: :secondary,
            timestamp: :supporting,
            decoration: :ambient
          }
        end
      end
    end
  end
end
