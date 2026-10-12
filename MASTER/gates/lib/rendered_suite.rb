# frozen_string_literal: true

require_relative "../support/gate_result"
require_relative "../support/gate_autofix"
require_relative "rendered/browser_diagnostics"
require_relative "rendered/rendered_geometry"
require_relative "rendered/layout_snapshot"
require_relative "rendered/journey_invariant"
require_relative "rendered/reflow"
require_relative "rendered/keyboard_flow"
require_relative "rendered/mobile_flow"
require_relative "rendered/cross_app"
require_relative "rendered/webgl_surfaces"
require_relative "rendered/viewport_spill"

module Deploy
  # Composite for every gate that measures a real browser.
  #
  # Kept separate from LayoutSuiteGate on purpose: that suite is pure source
  # analysis and runs in seconds anywhere, while these need Chrome and a booted
  # app. Grouping them means `runner.rb --all` on a machine with neither degrades
  # to warnings in one place instead of thirteen.
  #
  # Leaves that support mechanical fixes remeasure themselves; the suite then
  # re-runs everything once more if anything was patched.
  class RenderedSuiteGate
    LEAVES = [
      BrowserDiagnosticsGate,
      RenderedGeometryGate,
      ReflowGate,
      KeyboardFlowGate,
      MobileFlowGate,
      JourneyInvariantGate,
      CrossAppEquivalenceGate,
      LayoutSnapshotGate,
      ViewportSpillGate,
      # Last, because it is the only leaf that wants a GPU stack: it opens its
      # own session with SwiftShader rather than the shared --disable-gpu one.
      WebglSurfacesGate,
    ].freeze

    def self.run = new.run

    def run
      report = run_leaves
      return report if report.ok? || !GateAutofix.enabled?

      applied = GateAutofix.apply_failures(report.failures, dry: GateAutofix.dry_run?)
      return report unless applied.positive? && !GateAutofix.dry_run?

      report.warn("rendered_suite: suite-level autofix patched #{applied} file(s); full remeasure")
      run_leaves
    end

    def coverage_line(name, leaf)
      details = ["#{leaf.checks_ran} check(s)"]
      details << "#{leaf.failures.size} failure(s)" unless leaf.failures.empty?
      details << "#{leaf.soft_failures.size} soft finding(s)" unless leaf.soft_failures.empty?
      details << "#{leaf.unchecked.size} inconclusive item(s)" unless leaf.unchecked.empty?
      details << "#{leaf.live_skips} live skip(s)" if leaf.live_skips.positive?
      details << "#{leaf.errors.size} error(s)" unless leaf.errors.empty?
      "coverage0: rendered/#{name} #{leaf.outcome.to_s.upcase} — #{details.join(', ')}"
    end

    # No checked! of its own — merge! carries each leaf's count up, and this
    # class measures nothing itself.
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
