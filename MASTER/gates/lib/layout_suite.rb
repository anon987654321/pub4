# frozen_string_literal: true

require_relative "../support/gate_result"
require_relative "../support/gate_autofix"
require_relative "source/css_constitution"
require_relative "source/scale_ratchet"
require_relative "source/css_brace_balance"
require_relative "source/css_minify_integrity"
require_relative "live/first_screen"
require_relative "source/dialect_purity"
require_relative "source/payment_honesty"
require_relative "source/affiliate_honesty"
require_relative "source/content_honesty"
require_relative "source/content_for_yield"
require_relative "research/layout_search"
require_relative "live/user_flow"
require_relative "live/surface_schema"
require_relative "research/design_metrics"
require_relative "research/visual_quality"
require_relative "research/calibration"
require_relative "source/frontend_auditor"
require_relative "source/stimulus_wiring"
require_relative "source/typography_contract"

module Deploy
  # Composite: every layout/CSS professional gate. CSS must pass constitution + auditor + dialect.
  # When GATE_AUTOFIX=1, leaves that support mechanical fix remeasure themselves;
  # the suite then re-runs the full leaf list once more after any patches.
  class LayoutSuiteGate
    LEAVES = [
      CssBraceBalanceGate,
      CssConstitutionGate,
      ScaleRatchetGate,
      CssMinifyIntegrityGate,
      DialectPurityGate,
      FirstScreenGate,
      LayoutSearchGate,
      PaymentHonestyGate,
      AffiliateHonestyGate,
      ContentHonestyGate,
      ContentForYieldGate,
      UserFlowGate,
      SurfaceSchemaGate,
      DesignMetricsGate,
      TypographyContractGate,
      VisualQualityGate,
      CalibrationGate,
      FrontendAuditorGate,
      StimulusWiringGate,
    ].freeze

    def self.run
      new.run
    end

    def run
      report = run_leaves
      return report if report.ok? || !GateAutofix.enabled?

      # Suite-level second pass after leaf autofix (css_constitution already remeasured).
      # Apply any remaining mechanical fixes from aggregated failures, then remeasure all leaves.
      applied = GateAutofix.apply_failures(report.failures, dry: GateAutofix.dry_run?)
      if applied.positive? && !GateAutofix.dry_run?
        report.warn("layout_suite: suite-level autofix patched #{applied} file(s); full remeasure")
        report = run_leaves
      end
      report
    end

    def coverage_line(name, leaf)
      details = ["#{leaf.checks_ran} check(s)"]
      details << "#{leaf.failures.size} failure(s)" unless leaf.failures.empty?
      details << "#{leaf.soft_failures.size} soft finding(s)" unless leaf.soft_failures.empty?
      details << "#{leaf.unchecked.size} inconclusive item(s)" unless leaf.unchecked.empty?
      details << "#{leaf.live_skips} live skip(s)" if leaf.live_skips.positive?
      details << "#{leaf.errors.size} error(s)" unless leaf.errors.empty?
      "coverage0: layout/#{name} #{leaf.outcome.to_s.upcase} — #{details.join(', ')}"
    end

    # No checked! of its own: a composite measured whatever its leaves
    # measured, and merge! carries their check counts up. Counting here as well
    # would claim a check this class never ran.
    def run_leaves
      result = GateResult.new
      LEAVES.each do |klass|
        name = klass.name.split("::").last
        leaf = begin
          klass.run
        rescue StandardError => e
          GateResult.from_error(e, gate: name)
        end
        result.warn(coverage_line(name, leaf))
        result.merge!(leaf, label: name)
      end
      result
    end
  end
end
