# frozen_string_literal: true

module Master
  module Core
    module Design
      # IconSystem defines the semantic language for iconography.
      # It ensures consistency in stroke, fill, and optical sizing.
      class IconSystem
        # Optical sizing scale
        SIZES = {
          xs: "12px",
          sm: "16px",
          md: "20px",
          lg: "24px",
          xl: "32px"
        }.freeze

        # Semantic icon categories to ensure a consistent language
        # instead of random SVG choices.
        CATEGORIES = {
          navigation: %i[home search map profile settings notifications],
          action: %i[send reply share save edit delete close],
          system: %i[expand collapse filter sort location camera mic attachment],
          brgen_districts: {
            marketplace: :object_tag,
            takeaway: :plate_bag,
            dating: :presence_person,
            music: :waveform_note,
            events: :calendar_time,
            maps: :spatial_marker
          }
        }.freeze

        def self.valid_size?(size)
          SIZES.key?(size.to_sym)
        end

        def self.valid_icon?(category, icon)
          return false unless CATEGORIES.key?(category.to_sym)
          list = CATEGORIES[category.to_sym]
          list.is_a?(Hash) ? list.values.include?(icon.to_sym) : list.include?(icon.to_sym)
        end
      end
    end
  end
end
