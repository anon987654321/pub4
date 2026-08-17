# frozen_string_literal: true

require_relative "../../../OPENBSD/lib/gate_result"
require_relative "../support/gate_autofix"
require_relative "rendered_geometry"
require_relative "layout_snapshot"
require_relative "journey_invariant"
require_relative "reflow"
require_relative "keyboard_flow"
require_relative "mobile_flow"
require_relative "cross_app"

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
      RenderedGeometryGate,
      ReflowGate,
      KeyboardFlowGate,
      MobileFlowGate,
      JourneyInvariantGate,
      CrossAppEquivalenceGate,
      LayoutSnapshotGate,
    ].freeze

    def self.run = new.run

    def run
      result = run_leaves
      return result if result.ok? || !GateAutofix.enabled?

      applied = GateAutofix.apply_failures(result.failures, dry: GateAutofix.dry_run?)
      return result unless applied.positive? && !GateAutofix.dry_run?

      result.warn("rendered_suite: suite-level autofix patched #{applied} file(s); full remeasure")
      run_leaves
    end

    def run_leaves
      result = GateResult.new
      LEAVES.each do |klass|
        name = klass.name.split("::").last
        leaf = begin
          klass.run
        rescue StandardError => e
          failed = GateResult.new
          failed.fail("#{name} raised #{e.class}: #{e.message}")
          failed
        end
        result.merge!(leaf, label: name)
      end
      result
    end
  end
end
