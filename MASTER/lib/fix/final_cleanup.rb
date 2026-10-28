# frozen_string_literal: true

require "time"

module Master
  module Fix
    # The final /fix stage releases run-owned resources and prunes only the
    # checksum-addressed reports owned by the bounded run journal. Source files,
    # checkpoints, transactions, the audit ledger and test evidence are retained.
    class FinalCleanup
      def initialize(root:, bus: nil, kernel: nil, committer: nil, pass_runner: nil, run_journal: nil)
        @root = File.expand_path(root)
        @bus = bus
        @kernel = kernel
        @committer = committer
        @pass_runner = pass_runner
        @run_journal = run_journal
      end

      def run(target:, run_id: nil, terminal_state: nil)
        completed = []
        skipped = []
        warnings = []

        step("commit_lease", completed, skipped, warnings, available: @committer&.respond_to?(:lease_guard=)) do
          @committer.lease_guard = nil
        end
        step("visual_runtime", completed, skipped, warnings,
             available: @pass_runner&.respond_to?(:cleanup_visual_runtime)) do
          @pass_runner.cleanup_visual_runtime
        end
        step("visual_artifacts", completed, skipped, warnings,
             available: @pass_runner&.respond_to?(:cleanup_visual_artifacts)) do
          @pass_runner.cleanup_visual_artifacts
        end
        step("assessment_artifacts", completed, skipped, warnings,
             available: assessment_pruner_available?) do
          keep_limit = @run_journal.class.const_defined?(:MAX_RUNS, false) ?
            @run_journal.class.const_get(:MAX_RUNS, false) : 24
          keep_ids = @run_journal.history(limit: keep_limit).map do |entry|
            entry["id"] || entry[:id]
          end.compact
          @run_journal.prune_assessment_reports!(keep_ids:)
        end
        step("architecture_artifacts", completed, skipped, warnings,
             available: @run_journal&.respond_to?(:prune_architecture_reports!)) do
          @run_journal.prune_architecture_reports!
        end

        receipt = {
          run_id: run_id,
          target: target_label(target),
          terminal_state: terminal_state&.to_s || "not_terminalized",
          status: warnings.empty? ? "clean" : "warning",
          completed: completed,
          skipped: skipped,
          warnings: warnings,
          finished_at: Time.now.utc.iso8601(6),
        }

        begin
          @kernel&.append_event(
            receipt[:status] == "clean" ? "cleanup_completed" : "cleanup_warning",
            receipt,
            run_id: run_id,
          )
        rescue StandardError => error
          warnings << warning("cleanup_receipt", error)
          receipt[:status] = "warning"
          receipt[:warnings] = warnings
        end

        @bus&.publish("fix_loop:cleanup", **receipt)
        if defined?(Master::Trace::Dmesg)
          Master::Trace::Dmesg.status(
            "cleanup0",
            "#{receipt[:status]} run=#{run_id || 'preflight'} " \
              "completed=#{completed.join(',') || 'none'} skipped=#{skipped.size} warnings=#{warnings.size}",
          )
        end
        receipt
      rescue StandardError => error
        # This last-resort guard must never mask the repair outcome or its exception.
        fallback = {
          run_id: run_id,
          target: target_label(target),
          terminal_state: terminal_state&.to_s || "not_terminalized",
          status: "warning",
          completed: [],
          skipped: [],
          warnings: [warning("cleanup_stage", error)],
          finished_at: Time.now.utc.iso8601(6),
        }
        @bus&.publish("fix_loop:cleanup", **fallback)
        Master::Trace::Dmesg.status("cleanup0", "warning, stage failed: #{error.class}: #{error.message.to_s[0, 160]}") if
          defined?(Master::Trace::Dmesg)
        fallback
      end

      private

      def step(name, completed, skipped, warnings, available:)
        unless available
          skipped << name
          return
        end

        yield
        completed << name
      rescue StandardError => error
        warnings << warning(name, error)
      end

      def assessment_pruner_available?
        @run_journal&.respond_to?(:history) && @run_journal.respond_to?(:prune_assessment_reports!)
      end

      def warning(step, error)
        {
          step: step,
          error_class: error.class.name,
          message: error.message.to_s.gsub(/\s+/, " ").strip[0, 160],
        }
      end

      def target_label(target)
        expanded = File.expand_path(target.to_s, @root)
        return "." if expanded == @root
        return expanded.delete_prefix(@root + File::SEPARATOR) if expanded.start_with?(@root + File::SEPARATOR)

        "(external target)"
      end
    end
  end
end
