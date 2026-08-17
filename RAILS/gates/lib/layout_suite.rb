# frozen_string_literal: true

require_relative "../../../OPENBSD/lib/gate_result"
require_relative "../support/gate_autofix"
require_relative "source/css_constitution"
require_relative "source/css_minify_integrity"
require_relative "live/first_screen"
require_relative "source/dialect_purity"
require_relative "source/payment_honesty"
require_relative "source/affiliate_honesty"
require_relative "source/content_honesty"
require_relative "research/layout_search"
require_relative "live/user_flow"
require_relative "live/surface_schema"
require_relative "research/design_metrics"
require_relative "research/visual_quality"
require_relative "research/calibration"
require_relative "source/frontend_auditor"
require_relative "source/stimulus_wiring"

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

