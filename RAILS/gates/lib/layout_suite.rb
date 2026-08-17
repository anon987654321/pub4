# frozen_string_literal: true

require_relative "../../../OPENBSD/lib/gate_result"
require_relative "../support/gate_autofix"
require_relative "css_constitution"
require_relative "css_minify_integrity"
require_relative "first_screen"
require_relative "dialect_purity"
require_relative "payment_honesty"
require_relative "affiliate_honesty"
require_relative "content_honesty"
require_relative "layout_search"
require_relative "user_flow"
require_relative "surface_schema"
require_relative "design_metrics"
require_relative "visual_quality"
require_relative "calibration"
require_relative "frontend_auditor"
require_relative "stimulus_wiring"

module Deploy
  # Composite: every layout/CSS professional gate. CSS must pass constitution + auditor + dialect.
  # When GATE_AUTOFIX=1, leaves that support mechanical fix remeasure themselves;
  # the suite then re-runs the full leaf list once more after any patches.
  class LayoutSuiteGate
    LEAVES = [
      CssConstitutionGate,
      CssMinifyIntegrityGate,
      DialectPurityGate,
      FirstScreenGate,
      LayoutSearchGate,
      PaymentHonestyGate,
      AffiliateHonestyGate,
      ContentHonestyGate,
      UserFlowGate,
      SurfaceSchemaGate,
      DesignMetricsGate,
      VisualQualityGate,
      CalibrationGate,
      FrontendAuditorGate,
      StimulusWiringGate,
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
        result.merge!(klass.run, label: klass.name.split("::").last)
      end
      result
    end
  end
end

