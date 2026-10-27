# frozen_string_literal: true

require_relative "../support/check_result"
require_relative "../support/check_autofix"
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
require_relative "rendered_suite"

module Deploy
  # Composite: source laws plus rendered evidence. CSS must pass constitution + auditor + dialect.
  # When CHECK_AUTOFIX=1, leaves that support mechanical fix remeasure themselves;
  # the suite then re-runs the full leaf list once more after any patches.
  class LayoutSuiteCheck
    LEAVES = [
      CssBraceBalanceCheck,
      CssConstitutionCheck,
      ScaleRatchetCheck,
      CssMinifyIntegrityCheck,
      DialectPurityCheck,
      FirstScreenCheck,
      LayoutSearchCheck,
      PaymentHonestyCheck,
      AffiliateHonestyCheck,
      ContentHonestyCheck,
      ContentForYieldCheck,
      UserFlowCheck,
      SurfaceSchemaCheck,
      DesignMetricsCheck,
      TypographyContractCheck,
      VisualQualityCheck,
      CalibrationCheck,
      FrontendAuditorCheck,
      StimulusWiringCheck,
      RenderedSuiteCheck,
    ].freeze

    def self.run
      new.run
    end

    def run
      report = run_leaves
      return report if report.ok? || !CheckAutofix.enabled?

      # Suite-level second pass after leaf autofix (css_constitution already remeasured).
      # Apply any remaining mechanical fixes from aggregated failures, then remeasure all leaves.
      applied = CheckAutofix.apply_failures(report.failures, dry: CheckAutofix.dry_run?)
      if applied.positive? && !CheckAutofix.dry_run?
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

    # Source checks cannot certify a rendered layout. The composed browser suite
    # must actually compare live surfaces without skipped routes, inconclusive
    # measurements, missing baselines or soft visual findings.
    def require_rendered_evidence!(aggregate, leaf)
      reasons = []
      reasons << "outcome=#{leaf.outcome}" unless leaf.outcome == :passed

      reasons << "#{leaf.live_skips} live skip(s)" if leaf.live_skips.positive?
      unless leaf.unchecked.empty?
        reasons << "#{leaf.unchecked.size} inconclusive item(s), first: #{leaf.unchecked.first}"
      end
      reasons << "#{leaf.soft_failures.size} unapproved visual finding(s)" unless leaf.soft_failures.empty?
      reasons << "#{leaf.errors.size} check error(s)" unless leaf.errors.empty?
      reasons << "zero rendered checks" if leaf.checks_ran.zero?
      return if reasons.empty?

      aggregate.fail("layout_suite: rendered evidence is incomplete — #{reasons.join(', ')}")
    end

    # No checked! of its own: a composite measured whatever its leaves
    # measured, and merge! carries their check counts up. Counting here as well
    # would claim a check this class never ran.
    # CHECK_LANE=code (/fix --lane code) measures the source leaves only: the rendered
    # suite is the 214-cell browser sweep, and the visual lane is where it runs.
    def leaves
      return LEAVES unless ENV["CHECK_LANE"] == "code"

      LEAVES - [RenderedSuiteCheck]
    end

    def run_leaves
      result = CheckResult.new
      result.warn("coverage0: layout/RenderedSuiteCheck NOT RUN — lane=code; rendered evidence is the visual lane's") if
        leaves.size < LEAVES.size
      leaves.each do |klass|
        name = klass.name.split("::").last

        leaf = begin
          klass.run
        rescue StandardError => e
          CheckResult.from_error(e, check: name)
        end

        result.warn(coverage_line(name, leaf))
        result.merge!(leaf, label: name)
        require_rendered_evidence!(result, leaf) if klass == RenderedSuiteCheck
      end
      result
    end
  end
end
