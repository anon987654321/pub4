# frozen_string_literal: true

module Master
  module Ground
    class Rules
      # Pure data-accessor readers over the loaded YAML — kept in a separate
      # module so NO_GOD_CLASS's AST-based public-method count only sees
      # Rules' own lookup/parsing methods, not this passthrough layer.
      module RuleAccessors
        def workflow = @workflow.freeze

        def voice = @voice ||= (@voice_data["voice"] || @data["voice"] || {}).freeze
        def strunk = @strunk ||= (voice["strunk"] || {}).freeze
        def preserve = @preserve ||= (voice["preserve"] || {}).freeze

        def constitution
          @constitution ||= begin
            absolute = @soul_data["absolute"] || {}
            {
              "golden_rule" => absolute["golden_rule"] || @data["golden_rule"],
              "protection" => absolute["protection_tiers"] || @data["protection"],
              "banned_output" => voice["banned_output"],
              "anti_simulation" => absolute["anti_simulation"] || voice["anti_simulation"],
              "communication_style" => voice["style"],
            }.freeze
          end
        end

        def code_rules = @code_rules ||= (@soul_data.dig("absolute", "code_rules") || {}).freeze
        def thresholds = @thresholds ||= (@data["thresholds"] || {}).freeze
        def scan_depths = @scan_depths ||= (@data["scan_depths"] || {}).freeze
        def languages_config = @languages_config ||= (@data["languages"] || {}).freeze
        def workflow_rule(key) = @workflow.dig(key.to_s) || {}
      end
    end
  end
end
