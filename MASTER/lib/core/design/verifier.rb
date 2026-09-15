# frozen_string_literal: true

module Master
  module Core
    module Design
      # The VisualVerifier measures the UI against a set of deterministic invariants.
      # It transforms "beauty" into "constraint-perfection."
      class VisualVerifier
        def initialize(container)
          @container = container
          @hierarchy_verifier = HierarchyVerifier.new(container)
          @optical_engine = OpticalAlignmentEngine
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
          
          # 3. Optical Alignment Check
          optical_errors = []
          interactive_elements.each do |e|
            correction = @optical_engine.calculate_correction(e)
            optical_errors << e[:id] if correction[:x_offset].abs > 1.5 || correction[:y_offset].abs > 1.5
          end
          
          if optical_errors.any?
            results[:failed] << "optical_misalignment"
            results[:metrics][:optical_errors] = optical_errors.size
          else
            results[:passed] << "optically_aligned"
          end
          
          # 4. Hierarchy Check
          if screenshot_data[:hierarchy]
            h_violations = @hierarchy_verifier.verify(screenshot_data[:hierarchy])
            results[:failed] += h_violations.map { |v| v[:type].to_s }
            results[:metrics][:hierarchy_violations] = h_violations.size
          end
          
          results
        end
      end
    end
  end
end

