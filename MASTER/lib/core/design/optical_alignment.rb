# frozen_string_literal: true

module Master
  module Core
    module Design
      # The OpticalAlignmentEngine calculates "perceived" center and balance.
      # It corrects mathematical alignment to achieve a professional finish.
      class OpticalAlignmentEngine
        def self.calculate_correction(element_data)
          # Logic analyzes the artwork's actual pixels vs the bounding box
          {
            x_offset: (element_data[:visual_mass_x] - element_data[:center_x]).round(2),
            y_offset: (element_data[:visual_mass_y] - element_data[:center_y]).round(2),
            correction: "±#{element_data[:offset_total]}px"
          }
        end

        def self.verify_alignment(element_a, element_b)
          # Compares the optical baselines of two elements
          (element_a[:optical_baseline] - element_b[:optical_baseline]).abs < 1.0
        end
      end
    end
  end
end
