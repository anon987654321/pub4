# frozen_string_literal: true

require "yaml"

module Master
  module Fix
    # Runtime boundary for the operator-authorized Rails layout-completion
    # campaign. The campaign permits measured layout repairs, not a free-form
    # redesign and not edits to canonical visual tokens.
    module VisualCompletion
      POLICY_PATH = "RAILS/visual_completion.yml"
      ELIGIBLE_EXTENSIONS = %w[.css .scss .erb .html .htm].freeze
      # Spelled to match the law catalogue's actual IDs (data/laws.yml); see
      # VisualCustodyBlocking::OPERATOR_OWNED_RULE_IDS for why. A finding's
      # real law_id is never literally "TYPE_SCALE" or "LEADING", so this list
      # previously could not authorize anything in those categories — the
      # policy YAML's own allowed_visual_rules still names the old spellings,
      # so this correction alone does not newly authorize autofix; it makes
      # authorized_visual_rule? check against IDs a finding can actually carry.
      ALLOWED_VISUAL_RULES = %w[
        AESTHETIC_FLAT_SEMANTIC
        TYPE_HIERARCHY
        LINE_HEIGHT_ON_SCALE
        NO_DECORATIVE_FX
        SQUINT_TEST
        EIGHT_PX_RHYTHM
      ].freeze

      PROMPT = <<~TEXT.freeze
        AUTHORIZED RAILS LAYOUT COMPLETION
        This is an explicit, bounded request to finish incomplete Rails layouts professionally, not merely make the scanner green.
        Improve task-first hierarchy, alignment, existing-token spacing rhythm, responsive composition, content density, forms, navigation, and meaningful empty/loading/validation/error/success states where current evidence shows a defect.
        Treat mobile as the primary composition. Preserve keyboard operation, visible focus, touch targets, safe areas, reduced motion, Norwegian localization, and worst-case content.
        Preserve each application's existing product dialect and interaction contracts. Reuse existing components, primitives, and tokens. Do not introduce a new visual system, arbitrary one-off design values, decorative effects, or a new dependency.
        This authorization permits measured layout, type-scale, leading, rhythm, and decorative-noise repairs in eligible Rails frontend files only. Palette/semantic-colour changes, font-family changes, canonical token edits, brand changes, and behavior/content changes outside the finding remain operator-owned; stop and state the exact decision needed.
        Require live Chrome/CDP measurements before and after each visual change. Judge console/network failures, overflow, focus order, contrast, touch size, localization, shared chrome drift, and visual score. A source scan or screenshot alone is not completion evidence. If the browser, baseline, focused test, or required measurement is unavailable, say INCONCLUSIVE and keep the original change.
      TEXT

      module_function

      def policy(root:)
        path = File.join(repo_root(root), POLICY_PATH)
        return {} unless File.file?(path)

        value = YAML.safe_load_file(path, aliases: false)
        value.is_a?(Hash) ? value : {}
      rescue ArgumentError, Psych::Exception, SystemCallError
        {}
      end

      def enabled_for_target?(root:, target:)
        config = policy(root:)
        return false unless authorized_policy?(config)

        relative = relative_path(root:, path: target)
        return false unless relative == "RAILS"
        return false if excluded?(relative, config)

        true
      end

      def frontend_campaign_path?(root:, path:)
        config = policy(root:)
        return false unless authorized_policy?(config)
        return false unless ELIGIBLE_EXTENSIONS.include?(File.extname(path.to_s).downcase)

        relative = relative_path(root:, path:)
        relative && relative.start_with?("RAILS/") && !excluded?(relative, config)
      end

      def enabled_for_path?(root:, path:)
        relative = relative_path(root:, path:)
        frontend_campaign_path?(root:, path:) && !canonical_token_path?(relative)
      end

      def authorized_visual_rule?(rule_id, root:, path:, custody:)
        return false unless ALLOWED_VISUAL_RULES.include?(rule_id.to_s)
        return false unless custody&.respond_to?(:layout_completion?) && custody.layout_completion?
        return false unless enabled_for_path?(root:, path:)

        declared = Array(policy(root:).fetch("allowed_visual_rules", [])).map(&:to_s)
        declared.include?(rule_id.to_s)
      end

      def prompt_context(root:, path:, custody:)
        return "" unless custody&.respond_to?(:layout_completion?) && custody.layout_completion?
        return "" unless enabled_for_path?(root:, path:)

        PROMPT
      end

      # Enforce the ownership boundary on the candidate itself, not only
      # through prompt wording. Styling values that determine identity stay
      # fixed while permitted layout properties change.
      def change_blocker(root:, path:, before:, after:, custody:)
        return unless custody&.respond_to?(:layout_completion?) && custody.layout_completion?
        return unless frontend_campaign_path?(root:, path:)
        return "canonical visual tokens are operator-owned" if canonical_token_path?(relative_path(root:, path:))

        prior = protected_visual_signatures(before)
        proposed = protected_visual_signatures(after)
        return unless prior != proposed

        "palette/semantic colours and font-family are operator-owned; preserve existing declarations"
      end

      COLOR_PROPERTIES = %w[
        color background background-color background-image border border-color
        border-top border-right border-bottom border-left border-top-color
        border-right-color border-bottom-color border-left-color outline
        outline-color text-decoration-color text-shadow box-shadow fill stroke
        caret-color accent-color
      ].freeze
      COLOR_TOKEN = /#[0-9a-f]{3,8}\b|(?:rgba?|hsla?)\s*\([^)]*\)|\b(?:transparent|currentcolor|black|white|red|green|blue|yellow|orange|purple|gray|grey)\b|var\(\s*--[\w-]+\s*\)/i

      def protected_visual_signatures(source)
        color_rows = []
        font_rows = []
        declarations = source.to_s.split(/[;{}]/)
        source.to_s.scan(/style\s*=\s*["']([^"']*)["']/i).flatten.each { |inline| declarations.concat(inline.split(";")) }
        declarations.each do |declaration|
          name, value = declaration.split(":", 2)
          next unless name && value

          property = name.strip.downcase
          value = value.strip
          next if value.empty?

          if COLOR_PROPERTIES.include?(property)
            tokens = value.scan(COLOR_TOKEN).map(&:downcase)
            color_rows << [property, tokens.empty? ? value.gsub(/\s+/, " ").downcase : tokens]
          elsif property == "font-family"
            font_rows << value.gsub(/\s+/, " ").strip
          end
        end
        [color_rows.sort_by(&:inspect), font_rows.sort]
      end
      private_class_method :protected_visual_signatures

      def repo_root(root)
        expanded = File.expand_path(root.to_s)
        File.basename(expanded) == "MASTER" ? File.expand_path("..", expanded) : expanded
      end

      def relative_path(root:, path:)
        repo = repo_root(root)
        value = path.to_s
        candidate = value.start_with?(File::SEPARATOR) ? File.expand_path(value) : File.expand_path(value, repo)
        return candidate.delete_prefix("#{repo}/") if candidate.start_with?("#{repo}/")

        candidate == repo ? "." : nil
      rescue ArgumentError
        nil
      end

      def canonical_token_path?(relative)
        relative.match?(%r{\ARAILS/(?:__shared|shared)/app/assets/stylesheets/_dialect_tokens\.scss\z})
      end

      def authorized_policy?(config)
        return false unless config["schema"].to_i == 1 && config["enabled"] == true
        return false unless config["target"].to_s == "RAILS"

        constraints = config.fetch("constraints", {})
        verification = config.fetch("verification", {})
        return false unless constraints.is_a?(Hash) && verification.is_a?(Hash)

        constraints["preserve_product_dialects"] == true &&
          constraints["use_existing_tokens_and_primitives"] == true &&
          constraints["canonical_tokens_are_immutable"] == true &&
          constraints["palette_and_font_family_are_operator_owned"] == true &&
          constraints["semantic_color_changes_are_operator_owned"] == true &&
          constraints["mobile_first"] == true &&
          constraints["keyboard_and_reduced_motion"] == true &&
          constraints["preserve_interactions_and_localization"] == true &&
          verification["require_measurable_browser"] == true &&
          verification["require_accessible_and_functional_states"] == true &&
          verification["require_focused_tests"] == true &&
          verification["permit_snapshot_promotion_after_quality_pass"] == true &&
          verification["promote_missing_or_unmeasurable_baselines"] == false
      rescue NoMethodError
        false
      end

      def excluded?(relative, config)
        Array(config["exclude"]).map(&:to_s).any? do |prefix|
          relative == prefix || relative.start_with?("#{prefix}/")
        end
      end
    end
  end
end
