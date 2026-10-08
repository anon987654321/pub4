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
      OPERATOR_OWNED_LAW_IDS = %w[
        COLOR_CONTRAST
        AESTHETIC_FLAT_SEMANTIC
        TYPE_SCALE
        LEADING
        NO_DECORATIVE_FX
        SQUINT_TEST
        PIXEL_PERFECTION_RHYTHM
      ].freeze

      # Is this rule's repair blocked on operator decision?
      def fix_blocking_law?(law_id)
        OPERATOR_OWNED_LAW_IDS.include?(law_id.to_s)
      end

      # User-facing reason why the repair is blocked.
      def blocking_reason(law_id)
        if fix_blocking_law?(law_id)
          "rendered_value_decision_required — #{law_id} modifies operator-owned visual or design values"
        else
          nil
        end
      end

      # Prepare a finding for operator review when it's blocked.
      def prepare_operator_review(finding)
        law_id = finding.respond_to?(:law_id) ? finding.law_id : finding[:law]
        path = finding.respond_to?(:path) ? finding.path : finding[:file]
        severity = finding.respond_to?(:severity) ? finding.severity : finding[:severity]
        {
          "law_id" => law_id.to_s,
          "path" => path,
          "severity" => severity.to_s,
          "reason" => "This law modifies rendered values owned by the operator",
          "decision_needed" => "operator_approval",
          "guidance" => "Run '/why #{law_id}' to review the law; then decide whether to approve or defer"
        }
      end
    end
  end
end
