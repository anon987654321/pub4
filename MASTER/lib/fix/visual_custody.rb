# frozen_string_literal: true

require "json"
require_relative "../result"
require_relative "../gap"
require_relative "visual_quality_gates"
require_relative "../../gates/support/geometry_probe"
require_relative "../../gates/support/surface_probes"
require_relative "../../gates/lib/rendered/layout_snapshot"

module Master
  module Fix
    # A visual fix gets a stricter commit boundary than a source-only fix.
    # The committed layout snapshot is the protected surface contract: it must
    # match before a visual proposal is trusted, and it must still match after
    # the proposal is written. A mismatch restores the old source through
    # RepairLoop#reject_fix instead of blessing the new render.
    class VisualCustody
      # Nothing was measured and no measurement here will change that without
      # someone fixing the setup: a fact, not a decision.
      UNMEASURABLE = Gap.new(horizon: :never, cost_to_check: :minutes)

      attr_reader :surfaces

      def initialize(root:, surfaces:, bus: nil)
        @root = root
        @surfaces = Array(surfaces).select(&:snapshot).uniq
        @bus = bus
        @snapshot_gate = Deploy::LayoutSnapshotGate.new
      end

      def preflight!(captures)
        VisualQualityGates.record(captures, root: @root)
        compare_captures(Array(captures), "before visual fix")
      end

      def verify!(anchors: [])
        return Result.err("visual custody: no snapshot surfaces", category: :inconclusive, gap: UNMEASURABLE) if @surfaces.empty?
        return unavailable unless Deploy::GeometryProbe.available?

        measured = []
        Deploy::GeometryProbe.with_browser(root: @root, warm: @surfaces) do |cdp|
          @surfaces.each do |surface|
            measured << [surface, Deploy::SurfaceProbes.attach(cdp, surface, Deploy::GeometryProbe.walk(cdp, surface))]
          end
        end
        VisualQualityGates.judge(measured, root: @root, prior: compare_payloads(measured, "after visual fix"), anchors:)
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "fix.visual_custody", event_bus: @bus)
        Result.err("visual custody: INCONCLUSIVE — #{e.class}: #{e.message}", category: :inconclusive, gap: UNMEASURABLE)
      end

      private

      def compare_captures(captures, label)
        rows = captures.filter_map do |capture|
          surface = capture[:surface]
          next unless @surfaces.include?(surface)
          next unless capture.dig(:payload, "composition", "state") == "resting"
          [surface, capture[:payload]]
        end
        compare_payloads(rows, label)
      end

      def compare_payloads(rows, label)
        return Result.err("visual custody: no rendered snapshot payloads", category: :inconclusive, gap: UNMEASURABLE) if rows.empty?

        checked = 0
        missing = []
        failures = rows.filter_map do |surface, payload|
          path = baseline_path(surface)
          unless File.file?(path)
            missing << "#{surface.id}: missing committed baseline #{relative(path)}"
            next
          end

          unless Deploy::GeometryProbe.ok?(payload)
            next "#{surface.id}: render was not measurable: #{payload["error"] || "unknown probe error"}"
          end

          baseline = JSON.parse(File.read(path))
          current = @snapshot_gate.send(:distill, payload)
          diffs = @snapshot_gate.send(:compare, baseline, current)
          checked += 1
          next if diffs.empty?

          "#{surface.id}: #{diffs.first(6).join("; ")}"
        end

        return Result.err(
          "visual custody: #{label} has no committed baseline — #{missing.join(" / ")}",
          category: :inconclusive,
          gap: Gap::OPERATOR_DECISION, # a baseline is a rendered value; seeding one is the operator's call
        ) if missing.any?

        return Result.ok(state: :preserved, checked:, label:) if failures.empty?

        @bus&.publish("fix_loop:visual_custody_blocked", label:, surfaces: failures)
        Result.err(
          "visual custody: #{label} differs from committed baseline — #{failures.join(" / ")}",
          category: :policy,
          gap: Gap::OPERATOR_DECISION, # keep the change by blessing a new baseline, or revert it
        )
      rescue JSON::ParserError => e
        Result.err("visual custody: committed baseline unreadable: #{e.message}", category: :inconclusive, gap: UNMEASURABLE)
      end

      def baseline_path(surface)
        @snapshot_gate.send(:baseline_path, surface)
      end

      def relative(path)
        path.delete_prefix("#{@root}/")
      end

      def unavailable
        Result.err("visual custody: no Chrome/Chromium — rendered baseline cannot be verified", category: :inconclusive, gap: Gap::NO_BROWSER)
      end
    end
  end
end
