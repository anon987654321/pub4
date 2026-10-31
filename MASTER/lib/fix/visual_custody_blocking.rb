# frozen_string_literal: true

require_relative "visual_completion"

module Master
  module Fix
    # Rendered values (palette, font family, sound parameters, canonical tokens)
    # remain operator-owned. Only the separately recorded Rails completion campaign
    # may authorize its narrow layout/type-rhythm rules, and only with active visual
    # custody; all other findings still wait for an explicit operator decision.
    module VisualCustodyBlocking
      module_function

      # Rules that operate on rendered/visual values. These rules may find
      # violations, but /fix must not apply repairs without operator decision.
      #
      # Spelled to match the law catalogue's actual IDs (data/laws.yml), not
      # the campaign's descriptive names. CONTRAST_TOKENS, TYPE_HIERARCHY,
      # LINE_HEIGHT_ON_SCALE and EIGHT_PX_RHYTHM are what a real finding's
      # law_id carries; the prior COLOR_CONTRAST/TYPE_SCALE/LEADING/
      # PIXEL_PERFECTION_RHYTHM spellings never match one, so fix_blocking_rule?
      # silently returned false for every finding in these five categories —
      # the operator-decision gate RENDERED_VALUES exists to enforce was dead
      # for exactly the findings it was written to hold.
      OPERATOR_OWNED_RULE_IDS = %w[
        CONTRAST_TOKENS
        AESTHETIC_FLAT_SEMANTIC
        TYPE_HIERARCHY
        LINE_HEIGHT_ON_SCALE
        NO_DECORATIVE_FX
        SQUINT_TEST
        EIGHT_PX_RHYTHM
      ].freeze

      # Is this rule's repair blocked on operator decision?
      def fix_blocking_rule?(rule_id)
        OPERATOR_OWNED_RULE_IDS.include?(rule_id.to_s)
      end

      # The gap a blocked finding carries: no measurement settles it, a person decides.
      def gap_for(rule_id, root: Master::ROOT, path: nil, custody: nil)
        return unless fix_blocking_rule?(rule_id)

        return if path && VisualCompletion.authorized_visual_rule?(
          rule_id, root:, path:, custody:
        )

        Master::Gap::OPERATOR_DECISION
      end

      # User-facing reason why the repair is blocked.
      def blocking_reason(rule_id)
        if fix_blocking_rule?(rule_id)
          "rendered_value_decision_required — #{rule_id} modifies operator-owned visual or design values"
        else
          nil
        end
      end

      # Prepare a finding for operator review when it's blocked.
      def prepare_operator_review(finding)
        rule_id = finding.respond_to?(:law_id) ? finding.law_id : finding[:law]
        path = finding.respond_to?(:path) ? finding.path : finding[:file]
        severity = finding.respond_to?(:severity) ? finding.severity : finding[:severity]
        {
          "rule_id" => rule_id.to_s,
          "path" => path,
          "severity" => severity.to_s,
          "reason" => "This rule modifies rendered values owned by the operator",
          "decision_needed" => "operator_approval",
          "guidance" => "Run '/why #{rule_id}' to review the rule; then decide whether to approve or defer",
        }
      end
    end
  end
end
