# frozen_string_literal: true

module Master
  module Core
    module Design
      # The VisualEntropyAnalyzer measures the "design drift" of a surface.
      # It counts the number of unique visual tokens used.
      class VisualEntropyAnalyzer
        def self.analyze(surface_data)
          {
            font_families: surface_data[:fonts].uniq.size,
            font_weights: surface_data[:weights].uniq.size,
            colors: surface_data[:colors].uniq.size,
            radii: surface_data[:radii].uniq.size,
            shadows: surface_data[:shadows].uniq.size,
            spacing_values: surface_data[:spacing].uniq.size,
            icon_styles: surface_data[:icon_styles].uniq.size
          }
        end

        def self.detect_drift(analysis, budget)
          violations = []
          analysis.each do |key, value|
            if budget[key] && value > budget[key]
            violations << { property: key, value: value, budget: budget[key] }
            end
          end
          violations
        end
      end
    end
  end
end
