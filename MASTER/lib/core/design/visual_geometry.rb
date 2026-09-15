# frozen_string_literal: true

module Master
  module Core
    module Design
      # The VisualGeometry analyzes the physical properties of rendered elements.
      # It focuses on "optical" rather than "mathematical" alignment.
      class VisualGeometry
        def self.analyze_element(element_data)
          {
            bounding_box: element_data[:bbox],
            optical_center: calculate_optical_center(element_data),
            baseline: element_data[:baseline],
            whitespace_ratio: calculate_whitespace(element_data),
            visual_weight: calculate_weight(element_data)
          }
        end

        def self.calculate_optical_center(data)
          # Adjusts mathematical center based on visual mass (e.g., icons, typography)
          # Logic would involve analyzing the alpha channel of the rendered pixels
          data[:center].dup.tap do |c|
            c[:y] += (data[:visual_offset_y] || 0)
            c[:x] += (data[:visual_offset_x] || 0)
          end
        end

        def self.calculate_whitespace(data)
          # Ratio of content area to bounding box
          data[:content_area].to_f / data[:bbox_area].to_f
        end

        def self.calculate_weight(data)
          # Sum of dark pixels / total area
          data[:dark_pixel_count].to_f / data[:bbox_area].to_f
        end
      end
    end
  end
end
