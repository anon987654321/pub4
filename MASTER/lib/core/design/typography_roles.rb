# frozen_string_literal: true

module Master
  module Core
    module Design
      # TypographyRoles defines the semantic roles for text.
      # This prevents arbitrary font-size declarations and ensures
      # a consistent typographic hierarchy across all products.
      class TypographyRoles
        ROLES = {
          display: { weight: :bold, usage: "Hero headlines" },
          page_title: { weight: :semibold, usage: "Main page headers" },
          section_title: { weight: :semibold, usage: "Subsection headers" },
          card_title: { weight: :medium, usage: "Listing or card headers" },
          body: { weight: :normal, usage: "Primary reading text" },
          body_small: { weight: :normal, usage: "Secondary reading text" },
          label: { weight: :medium, usage: "Form labels and tags" },
          meta: { weight: :normal, usage: "Timestamps, distance, breadcrumbs" },
          price: { weight: :bold, usage: "Currency and numerical values" },
          navigation: { weight: :medium, usage: "Menu and tab items" },
          micro: { weight: :normal, usage: "Legal, footnotes, captions" }
        }.freeze

        def self.valid_role?(role)
          ROLES.key?(role.to_sym)
        end
      end
    end
  end
end
