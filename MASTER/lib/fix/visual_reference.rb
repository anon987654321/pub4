# frozen_string_literal: true

module Master
  module Fix
    module VisualReference
      # Reference profiles are descriptive lenses, not scores, targets, or
      # imitation instructions. MASTER laws remain authoritative.
      PROFILES = {
        "x" => {
          name: "X-style product surface",
          signals: %w[
            strong_typographic_hierarchy
            persistent_navigation
            dense_content_stream
            clear_interaction_states
            responsive_reflow
            high_information_continuity
          ],
        },
        "joi" => {
          name: "Joi-style conversational surface",
          signals: %w[
            focused_primary_action
            low_navigation_friction
            conversational_hierarchy
            restrained_chrome
            clear_input_feedback
            responsive_composition
          ],
        },
        "kaufland" => {
          name: "Kaufland-style marketplace surface",
          signals: %w[
            strong_search_discovery
            explicit_category_hierarchy
            broad_catalogue_navigation
            campaign_tiles
            themed_category_entry_points
            dense_product_information
            persistent_purchase_context
            clear_price_quantity_relationships
            responsive_listing_reflow
          ],
        },
        "bol" => {
          name: "bol-style marketplace surface",
          signals: %w[
            clean_white_catalogue
            prominent_search
            clear_service_promises
            restrained_product_card_chrome
            recommendation_rails
            product_first_imagery
            consistent_filtering
            clean_information_density
          ],
        },
        "pangram" => {
          name: "Pangram Pangram type-direction reference",
          signals: %w[
            contemporary_grotesk
            neutral_with_character
            disciplined_weight_range
            strong_display_options
            modernist_rigor
            typographic_detail
          ],
        },
      }.freeze

      module_function

      def profiles
        PROFILES
      end

      def context
        <<~TEXT
          REFERENCE LENSES
          These reference profiles describe qualities commonly useful when reviewing mature product surfaces. They are not a scorecard, ranking, pixel target, or instruction to copy another product. MASTER laws remain authoritative. Use a reference lens only when the rendered evidence makes the corresponding quality relevant.

          #{PROFILES.map { |id, profile| "#{id}: #{profile[:name]} — #{profile[:signals].join(", ")}" }.join("
")}

          Report concrete rendered evidence and the applicable MASTER laws. Prefer
          the smallest repair that improves the product's own identity, content,
          accessibility, semantics, responsiveness, and interaction model.
        TEXT
      end
    end
  end
end
