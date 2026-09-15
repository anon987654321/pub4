# frozen_string_literal: true

module Master
  module Core
    module Design
      # The VisualVerifier measures the UI against a set of deterministic invariants.
      # It transforms "beauty" into "constraint-perfection."
      class VisualVerifier
        def initialize(container)
          @container = container
        end

        # Verifies a rendered UI state.
        def verify(screenshot_data, viewport_size)
          results = { passed: [], failed: [], metrics: {} }
          
          # 1. Check for horizontal overflow (The cardinal sin of PWA)
          if screenshot_data[:width] > viewport_size[:width]
            results[:failed] << "horizontal_overflow"
          else
            results[:passed] << "no_overflow"
          end
          
          # 2. Verify minimum touch target sizes (44px rule)
          interactive_elements = screenshot_data[:elements] || []
          invalid_targets = interactive_elements.select { |e| e[:height] < 44 || e[:width] < 44 }
          
          if invalid_targets.any?
            results[:failed] << "small_touch_targets"
            results[:metrics][:small_targets_count] = invalid_targets.size
          else
            results[:passed] << "touch_targets_valid"
          end
          
          # 3. Verify alignment consistency
          if screenshot_data[:alignment_drift] > 2 # pixels
            results[:failed] << "alignment_drift"
          else
            results[:passed] << "aligned"
          end
          
          results
        end
      end
    end
  end
end
