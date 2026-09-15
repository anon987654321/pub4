# frozen_string_literal: true

module Master
  module Core
    module Design
      # The LayoutGrammar defines a strictly limited spatial vocabulary.
      # By restricting the model to these values, we ensure consistency
      # and eliminate "random" CSS values.
      class LayoutGrammar
        # Spacing scale (multiples of 4px)
        SPACE = {
          xs: 4,
          s: 8,
          m: 12,
          l: 16,
          xl: 24,
          xxl: 32,
          huge: 48,
          gargantuan: 64
        }.freeze

        # Typography hierarchy
        TYPOGRAPHY = {
          display: { size: "2rem", weight: "bold", leading: "1.1" },
          title: { size: "1.25rem", weight: "semibold", leading: "1.2" },
          body: { size: "1rem", weight: "normal", leading: "1.5" },
          meta: { size: "0.875rem", weight: "normal", leading: "1.4" },
          label: { size: "0.75rem", weight: "medium", leading: "1.2" }
        }.freeze

        # Border Radii
        RADIUS = {
          none: "0px",
          subtle: "4px",
          medium: "8px",
          full: "9999px"
        }.freeze

        # Max Widths for content containment
        WIDTHS = {
          reading: "65ch",
          content: "800px",
          wide: "1200px",
          full: "100%"
        }.freeze

        # Alignment primitives
        ALIGN = %i[start center end stretch].freeze

        def self.validate(property, value)
          case property
          when :space then SPACE.values.include?(value)
          when :radius then RADIUS.values.include?(value)
          when :type then TYPOGRAPHY.keys.include?(value)
          when :width then WIDTHS.values.include?(value)
          when :align then ALIGN.include?(value)
          else false
          end
        end
      end
    end
  end
end
