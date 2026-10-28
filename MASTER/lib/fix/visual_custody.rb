# frozen_string_literal: true

require "json"
require_relative "../result"
require_relative "../gap"
require_relative "visual_quality_checks"
require_relative "../../checks/support/geometry_probe"
require_relative "../../checks/support/surface_probes"
require_relative "../../checks/lib/rendered/layout_snapshot"

module Master
  module Fix
    # A visual fix gets a stricter commit boundary than a source-only fix.
    # Ordinarily the committed snapshot must match before and after a proposal.
    # The explicitly authorized Rails completion campaign may reconcile a
    # structural difference, but only after measurable renders and every other
    # visual quality check passes; its snapshot write joins the active transaction.
    class VisualCustody
      # Nothing was measured and no measurement here will change that without
      # someone fixing the setup: a fact, not a decision.
      UNMEASURABLE = Gap.new(horizon: :never, cost_to_check: :minutes)

      attr_reader :surfaces

      def initialize(root:, surfaces:, bus: nil, layout_completion: false)
        @root = root
        @surfaces = Array(surfaces).select(&:snapshot).uniq
        @bus = bus
        @layout_completion = !!layout_completion
        @preflight_verified = false
        @snapshot_check = Deploy::LayoutSnapshotCheck.new
      end

      def layout_completion? = @layout_completion && @preflight_verified

      def preflight!(captures)
        @preflight_verified = false
        VisualQualityChecks.record(captures, root: @root)
        verdict = compare_captures(Array(captures), "before visual fix")
        if verdict.ok?
          @preflight_verified = true
          return verdict
        end
        return verdict unless @layout_completion && verdict.category == :policy

        plan = snapshot_update_plan(snapshot_rows(captures), require_stable_elements: false)
        return inconclusive("layout baseline drift could not be reconciled to measured surfaces") if plan.empty?

        @preflight_verified = true
        Result.ok(state: :layout_completion_baseline_drift, pending_snapshots: plan.size)
      rescue LayoutCompletionEvidenceMissing => e
        @preflight_verified = false
        inconclusive("layout completion baseline is not promotable: #{e.message}")
      rescue LayoutCompletionConflict => e
        @preflight_verified = false
        Result.err("layout completion requires a decision: #{e.message}", category: :policy, gap: Master::Gap::OPERATOR_DECISION)
      end

      def verify!(anchors: [], committer: nil)
        return Result.err("visual custody: no snapshot surfaces", category: :inconclusive, gap: UNMEASURABLE) if @surfaces.empty?
        return unavailable unless Deploy::GeometryProbe.available?

        measured = []
        Deploy::GeometryProbe.with_browser(root: @root, warm: @surfaces) do |cdp|
          @surfaces.each do |surface|
            measured << [surface, Deploy::SurfaceProbes.attach(cdp, surface, Deploy::GeometryProbe.walk(cdp, surface))]
          end
        end

        snapshot_verdict = compare_payloads(measured, "after visual fix")
        updates = {}
        prior = snapshot_verdict
        if snapshot_verdict.err? && layout_completion? && snapshot_verdict.category == :policy
          updates = snapshot_update_plan(measured)
          return Result.err("layout completion found no changed structural snapshots to reconcile", category: :inconclusive, gap: UNMEASURABLE) if updates.empty?
          prior = Result.ok(state: :authorized_layout_completion)
        end

        if updates.any?
          return Result.err("layout snapshot promotion requires the active /fix transaction", category: :policy, gap: Master::Gap::OPERATOR_DECISION) unless committer
          enlisted = committer.enlist_related_visual_baselines!(updates.keys)
          return enlisted unless enlisted.ok?
        end

        quality = VisualQualityChecks.judge(
          measured, root: @root, prior:, anchors:, allow_layout_change: updates.any? && layout_completion?
        )
        return quality unless quality.ok?
        return quality if updates.empty?

        original_bytes = updates.keys.to_h { |path| [path, File.binread(path)] }
        begin
          updates.each { |path, data| @snapshot_check.write(path, data) }
          observed = committer.observe_related_visual_baseline_writes!(updates.keys)
          raise observed.message unless observed.ok?
        rescue StandardError => e
          restore_snapshot_bytes(original_bytes)
          return Result.err("layout snapshot promotion failed and was restored: #{e.class}: #{e.message}", category: :infrastructure, gap: UNMEASURABLE)
        end

        @bus&.publish("fix_loop:layout_snapshot_promoted", paths: updates.keys.map { |path| relative(path) })
        Result.ok(state: :authorized_layout_completion, snapshots_updated: updates.size)
      rescue LayoutCompletionEvidenceMissing => e
        inconclusive("layout completion could not verify every snapshot: #{e.message}")
      rescue LayoutCompletionConflict => e
        Result.err("layout completion requires an operator decision: #{e.message}", category: :policy, gap: Master::Gap::OPERATOR_DECISION)
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

      class LayoutCompletionEvidenceMissing < StandardError; end
      class LayoutCompletionConflict < StandardError; end

      def snapshot_rows(captures)
        Array(captures).filter_map do |capture|
          next unless @surfaces.include?(capture[:surface])
          next unless capture.dig(:payload, "composition", "state") == "resting"

          [capture[:surface], capture[:payload]]
        end
      end

      # Build an all-or-nothing update plan. A missing baseline, bad HTTP
      # response, thin DOM, failed geometry walk, malformed snapshot, or shared
      # alias disagreement is never repaired by silently blessing a new render.
      def snapshot_update_plan(measured, require_stable_elements: true)
        raise LayoutCompletionEvidenceMissing, "no rendered surfaces" if measured.empty?

        grouped = {}
        measured.each do |surface, payload|
          raise LayoutCompletionEvidenceMissing, "#{surface.id}: geometry was not measurable" unless Deploy::GeometryProbe.ok?(payload)

          status = payload["status"].to_i
          unless status.zero? || status.between?(200, 399)
            raise LayoutCompletionEvidenceMissing, "#{surface.id}: HTTP #{status}"
          end

          path = baseline_path(surface)
          raise LayoutCompletionEvidenceMissing, "#{surface.id}: baseline missing" unless File.file?(path)

          baseline = JSON.parse(File.read(path))
          current = @snapshot_check.distill(payload)
          if require_stable_elements && current.fetch("elements", []).size < Deploy::LayoutSnapshotCheck::MIN_ELEMENTS
            raise LayoutCompletionEvidenceMissing, "#{surface.id}: fewer than #{Deploy::LayoutSnapshotCheck::MIN_ELEMENTS} stable elements"
          end

          if grouped.key?(path) && grouped.fetch(path).fetch(:current) != current
            raise LayoutCompletionConflict, "#{surface.id} disagrees with another surface sharing #{relative(path)}"
          end
          grouped[path] ||= { baseline:, current: }
        end

        grouped.filter_map do |path, row|
          changed = @snapshot_check.compare(row.fetch(:baseline), row.fetch(:current))
          [path, row.fetch(:current)] unless changed.empty?
        end.to_h
      rescue JSON::ParserError => e
        raise LayoutCompletionEvidenceMissing, "snapshot JSON is unreadable: #{e.message}"
      end

      def restore_snapshot_bytes(original_bytes)
        original_bytes.each { |path, bytes| File.binwrite(path, bytes) }
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "fix.visual_custody.restore_snapshots", event_bus: @bus, severity: :load_bearing)
        raise "could not restore structural snapshots: #{e.class}: #{e.message}"
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
          current = @snapshot_check.distill(payload)
          diffs = @snapshot_check.compare(baseline, current)
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
        @snapshot_check.baseline_path(surface)
      end

      def relative(path)
        path.delete_prefix("#{@root}/")
      end

      def inconclusive(message)
        Result.err("visual custody: INCONCLUSIVE — #{message}", category: :inconclusive, gap: UNMEASURABLE)
      end

      def unavailable
        Result.err("visual custody: no Chrome/Chromium — rendered baseline cannot be verified", category: :inconclusive, gap: Gap::NO_BROWSER)
      end
    end
  end
end
