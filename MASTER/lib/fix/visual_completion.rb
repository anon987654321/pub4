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
      ALLOWED_VISUAL_RULES = %w[
        AESTHETIC_FLAT_SEMANTIC
        TYPE_SCALE
        LEADING
        NO_DECORATIVE_FX
        SQUINT_TEST
        PIXEL_PERFECTION_RHYTHM
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
        return false unless config["schema"].to_i == 1 && config["enabled"] == true
        return false unless config["target"].to_s == "RAILS"

        relative = relative_path(root:, path: target)
        return false unless relative && (relative == "RAILS" || relative.start_with?("RAILS/"))
        return false if excluded?(relative, config)

        true
      end

      def enabled_for_path?(root:, path:)
        config = policy(root:)
        return false unless config["schema"].to_i == 1 && config["enabled"] == true
        return false unless config["target"].to_s == "RAILS"
        return false unless ELIGIBLE_EXTENSIONS.include?(File.extname(path.to_s).downcase)

        relative = relative_path(root:, path:)
        relative && relative.start_with?("RAILS/") && !excluded?(relative, config) && !canonical_token_path?(relative)
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

      def excluded?(relative, config)
        Array(config["exclude"]).map(&:to_s).any? do |prefix|
          relative == prefix || relative.start_with?("#{prefix}/")
        end
      end
    end
  end
end
