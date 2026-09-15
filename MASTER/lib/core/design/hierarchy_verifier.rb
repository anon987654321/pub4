# frozen_string_literal: true

module Master
  module Core
    module Design
      # The HierarchyVerifier ensures that visual prominence matches semantic importance.
      # It prevents "semantic inversion" where metadata is more visible than primary content.
      class HierarchyVerifier
        def initialize(container)
          @container = container
        end

        # Verifies the hierarchy of a rendered surface.
        def verify(hierarchy_map)
          violations = []
          
          # Rule: Primary elements must have higher visual weight than secondary.
          hierarchy_map[:primary].each do |p|
            hierarchy_map[:secondary].each do |s|
              if s[:visual_weight] > p[:visual_weight]
                violations << {
                  type: :semantic_inversion,
                  primary: p[:id],
                  secondary: s[:id],
                  message: "Secondary element #{s[:id]} has higher prominence than primary element #{p[:id]}"
                }
              end
            end
          end
          
          # Rule: No competing primary actions.
          if hierarchy_map[:primary].size > 1
            # Check if they are visually too similar in prominence
            p_nodes = hierarchy_map[:primary]
            if p_nodes.all? { |n| (n[:visual_weight] - p_nodes.first[:visual_weight]).abs < 0.1 }
              violations << { type: :competing_prominence, message: "Multiple primary actions have near-identical prominence" }
            end
          end
          
          violations
        end
      end
    end
  end
end
