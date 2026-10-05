# frozen_string_literal: true

module Master
  module Fix
    # Operator-owned rendered values blocking. Rendered values (colors, fonts,
    # sound parameters, layout constants) are owned by the operator, not by /fix.
    # Rules that would change these values must block and wait for explicit
    # operator approval before mutation.
    module VisualCustodyBlocking
      module_function

      # Rules that operate on rendered/visual values. These rules may find
      # violations, but /fix must not apply repairs without operator decision.
      OPERATOR_OWNED_RULE_IDS = %w[
        COLOR_CONTRAST
        AESTHETIC_FLAT_SEMANTIC
        TYPE_SCALE
        LEADING
        NO_DECORATIVE_FX
        SQUINT_TEST
        PIXEL_PERFECTION_RHYTHM
      ].freeze

      # Is this rule's repair blocked on operator decision?
      def fix_blocking_rule?(rule_id)
        OPERATOR_OWNED_RULE_IDS.include?(rule_id.to_s)
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
        {
          "rule_id" => finding.rule_id.to_s,
          "path" => finding.path,
          "severity" => finding.severity.to_s,
          "reason" => "This rule modifies rendered values owned by the operator",
          "decision_needed" => "operator_approval",
          "guidance" => "Run '/why #{finding.rule_id}' to review the rule; then decide whether to approve or defer"
        }
      end
    end
  end
end
