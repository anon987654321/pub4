# frozen_string_literal: true

require_relative "visual_groups"

module Master
  module Fix
    # /fix --lane visual: one sweep, its findings grouped by cause (VisualGroups), the mechanical
    # fixers (ScaleSnap, TapTargetPad) before the model, the model once per group left, and a
    # resweep as the proof. Outside effects are injected (World); VisualLaneWorld wires them.
    class VisualLane
      Outcome = Data.define(:groups, :findings, :report, :cleared, :remaining, :resweep)

      # sweep/resweep -> { findings: [text], urls: {surface id => url}, screenshots: {surface id => png} }
      # snap/pad ->(group) { nil when the fixer does not apply, else :applied or the reason it did not }
      # repair ->(group) { :applied or the reason the model's edit was not kept }
      World = Data.define(:sweep, :resweep, :snap, :pad, :repair)

      REPORT = File.join("MASTER", ".master", "visual_groups.json").freeze
      MODEL_GROUPS = Integer(ENV.fetch("MASTER_FIX_VISUAL_MODEL_GROUPS", "12"))
      # Approving a pixel baseline is the operator's call (tools/approve_visual_baselines.rb).
      OPERATOR_ONLY = /pixel baseline missing|approve_visual_baselines|CHECK_SNAPSHOT_UPDATE/
      FIXERS = { snap: "scale snap", pad: "tap-target pad" }.freeze
      SHOTS = 3
      CLEARED = "cleared by the resweep"

      def initialize(world:, repo_root:, say: ->(_) {}, stop: -> { false }, model_groups: MODEL_GROUPS)
        @world = world
        @repo_root = repo_root
        @say = say
        @stop = stop
        @model_groups = model_groups
        @model_calls = 0
      end

      def run
        before = @world.sweep.call
        groups = grouped(before)
        @say.call("#{before.fetch(:findings).size} rendered finding(s) in #{groups.size} group(s)")
        groups.each { |group| group.before = shots(group, before) }
        groups.each do |group|
          break if @stop.call

          settle(group)
        end

        after = groups.any?(&:repaired?) ? @world.resweep.call : nil
        prove(groups, after) if after
        finish(groups, { before:, after: })
      end

      private

      def grouped(sweep) = VisualGroups.build(sweep.fetch(:findings), urls: sweep.fetch(:urls, {}))

      def settle(group)
        if group.members.any?(OPERATOR_ONLY)
          return record(group, fix: :none, detail: "baseline approval is the operator's")
        end

        reasons = []
        FIXERS.each do |fixer, name|
          outcome = @world.public_send(fixer).call(group)
          next if outcome.nil?
          return record(group, fix: :mechanical, detail: "#{name} applied") if outcome == :applied

          reasons << "#{name}: #{outcome}"
        end
        ask_model(group, reasons)
      end

      def ask_model(group, reasons)
        if @model_calls >= @model_groups
          record(group, fix: :none, detail: (reasons + ["model budget of #{@model_groups} group(s) spent"]).join("; "))
          return
        end

        @model_calls += 1
        outcome = @world.repair.call(group)
        record(group, fix: outcome == :applied ? :model : :none, detail: (reasons + ["model: #{outcome}"]).join("; "))
      end

      def record(group, fix:, detail:)
        group.fix = fix
        group.fix_detail = detail
        @say.call("#{group.id} #{group.law} x#{group.member_count}: #{fix}, #{detail}")
      end

      # A repaired group is cleared only when the sweep after it no longer reports its key.
      def prove(groups, after)
        still = grouped(after).map(&:key)
        groups.each do |group|
          group.after = shots(group, after)
          next unless group.repaired?

          verdict = still.include?(group.key) ? "still reported after the resweep" : CLEARED
          group.fix_detail = "#{group.fix_detail}; #{verdict}"
        end
      end

      def shots(group, sweep)
        screenshots = sweep.fetch(:screenshots, {})
        group.surfaces.filter_map { |id| screenshots[id] }.first(SHOTS)
      end

      def write_report(groups, sweeps)
        counted = sweeps.transform_values do |sweep|
          sweep && { "findings" => sweep.fetch(:findings).size, "manifest" => sweep[:manifest] }
        end
        report = VisualGroups.report(groups, lane: :visual, sweeps: counted)
        VisualGroups.write(File.join(@repo_root, REPORT), report)
      end

      def finish(groups, sweeps)
        before, after = sweeps.values_at(:before, :after)
        path = write_report(groups, sweeps)

        cleared = groups.count { |group| group.fix_detail.to_s.end_with?(CLEARED) }
        remaining = after ? grouped(after).size : groups.size
        Outcome.new(groups: groups.size, findings: before.fetch(:findings).size, report: path, cleared:, remaining:,
                    resweep: !after.nil?)
      end
    end
  end
end
