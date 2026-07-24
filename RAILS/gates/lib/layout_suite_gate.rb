# frozen_string_literal: true

require_relative "../../../OPENBSD/lib/gate_result"
require_relative "gate_autofix"
require_relative "css_constitution_gate"
require_relative "layout_geometry_gate"
require_relative "dialect_purity_gate"
require_relative "payment_honesty_gate"
require_relative "layout_search_gate"
require_relative "user_flow_gate"
require_relative "surface_schema_gate"
require_relative "frontend_auditor_gate_logic"

module Deploy
  # Composite: every layout/CSS professional gate. CSS must pass constitution + auditor + dialect.
  # When GATE_AUTOFIX=1, leaves that support mechanical fix remeasure themselves;
  # the suite then re-runs the full leaf list once more after any patches.
  class LayoutSuiteGate
    LEAVES = [
      CssConstitutionGate,
      DialectPurityGate,
      LayoutGeometryGate,
      LayoutSearchGate,
      PaymentHonestyGate,
      UserFlowGate,
      SurfaceSchemaGate,
      FrontendAuditorGate,
    ].freeze

    def self.run
      new.run
    end

    def run
      result = run_leaves
      return result if result.ok? || !GateAutofix.enabled?

      # Suite-level second pass after leaf autofix (css_constitution already remeasured).
      # Apply any remaining mechanical fixes from aggregated failures, then remeasure all leaves.
      applied = GateAutofix.apply_failures(result.failures, dry: GateAutofix.dry_run?)
      if applied.positive? && !GateAutofix.dry_run?
        result.warn("layout_suite: suite-level autofix patched #{applied} file(s); full remeasure")
        result = run_leaves
      end
      result
    end

    def run_leaves
      result = GateResult.new
      LEAVES.each do |klass|
        leaf = klass.run
        leaf.failures.each { |f| result.fail("[#{klass.name.split('::').last}] #{f}") }
        leaf.warnings.each { |w| result.warn("[#{klass.name.split('::').last}] #{w}") }
      end
      result
    end
  end
end

