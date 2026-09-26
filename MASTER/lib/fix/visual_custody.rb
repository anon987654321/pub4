# frozen_string_literal: true

require "json"
require_relative "../result"
require_relative "../../gates/support/geometry_probe"
require_relative "../../gates/lib/rendered/layout_snapshot"

module Master
  module Fix
    # A visual fix gets a stricter commit boundary than a source-only fix.
    # The committed layout snapshot is the protected surface contract: it must
    # match before a visual proposal is trusted, and it must still match after
    # the proposal is written. A mismatch restores the old source through
    # RuleLoop#reject_fix instead of blessing the new render.
    class VisualCustody
      attr_reader :surfaces

      def initialize(root:, surfaces:, bus: nil)
        @root = root
        @surfaces = Array(surfaces).select(&:snapshot).uniq
        @bus = bus
        @snapshot_gate = Deploy::LayoutSnapshotGate.new
      end

      def preflight!(captures)
        compare_captures(Array(captures), "before visual fix")
      end

      def verify!
        return Result.err("visual custody: no snapshot surfaces", category: :inconclusive) if @surfaces.empty?
        return unavailable unless Deploy::GeometryProbe.available?

        measured = []
        Deploy::GeometryProbe.with_browser(root: @root, warm: @surfaces) do |cdp|
          @surfaces.each do |surface|
            measured << [surface, Deploy::GeometryProbe.walk(cdp, surface)]
          end
        end
        compare_payloads(measured, "after visual fix")
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "fix.visual_custody", event_bus: @bus)
        Result.err("visual custody: INCONCLUSIVE — #{e.class}: #{e.message}", category: :inconclusive)
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
        return Result.err("visual custody: no rendered snapshot payloads", category: :inconclusive) if rows.empty?

        checked = 0
        failures = rows.filter_map do |surface, payload|
          path = baseline_path(surface)
          unless File.file?(path)
            next "#{surface.id}: missing committed baseline #{relative(path)}"
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

        return Result.ok(state: :preserved, checked:, label:) if failures.empty?

        @bus&.publish("fix_loop:visual_custody_blocked", label:, surfaces: failures)
        Result.err(
          "visual custody: #{label} differs from committed baseline — #{failures.join(" / ")}",
          category: :policy,
        )
      rescue JSON::ParserError => e
        Result.err("visual custody: committed baseline unreadable: #{e.message}", category: :inconclusive)
      end

      def baseline_path(surface)
        @snapshot_gate.send(:baseline_path, surface)
      end

      def relative(path)
        path.delete_prefix("#{@root}/")
      end

      def unavailable
        Result.err("visual custody: no Chrome/Chromium — rendered baseline cannot be verified", category: :inconclusive)
      end
    end
  end
end
