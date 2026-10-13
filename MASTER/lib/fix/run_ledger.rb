# frozen_string_literal: true

module Master
  module Fix
    # What one /fix run has learned about its own model phase, kept in memory so
    # the rest of the run can act on it: why proposals were rejected (and how
    # often per file), which files ran out of wall-clock, and which lanes keep
    # failing. The 2026-10-12 runs fixed nothing and said only "0 fixed";
    # the reasons were in the log one line at a time and never added up.
    #
    # State is per process, which is per run.
    module RunLedger
      MAX_REJECTS_PER_FILE = 2
      LANE_FAILURES_BEFORE_DROP = 2
      FILE_BUDGET_S = 90

      @mutex = Mutex.new
      @reasons = Hash.new(0)
      @declined = Hash.new(0)
      @file_rejects = Hash.new(0)
      @timeouts = []
      @lane_failures = Hash.new(0)
      @max_files = nil

      class << self
        def reset!
          @mutex.synchronize do
            @reasons = Hash.new(0)
            @declined = Hash.new(0)
            @file_rejects = Hash.new(0)
            @timeouts = []
            @lane_failures = Hash.new(0)
            @max_files = nil
          end
        end

        # Wall-clock seconds one file may spend in the model phase.
        def file_budget_s
          Integer(ENV.fetch("MASTER_FIX_FILE_BUDGET_S", FILE_BUDGET_S.to_s), exception: false) || FILE_BUDGET_S
        end

        # --max-files N: how many files the model phase takes, easiest first.
        def max_files
          @max_files || Integer(ENV.fetch("MASTER_FIX_MAX_FILES", "0"), exception: false).then { |n| n&.positive? ? n : nil }
        end

        def max_files=(value)
          @max_files = Integer(value).positive? ? Integer(value) : nil
        end

        # One proposal turned down: the reason, counted overall and against the file.
        def reject(reason, file:, law: nil, bus: nil)
          @mutex.synchronize do
            @reasons[reason.to_s] += 1
            @file_rejects[file.to_s] += 1
          end
          Master::Trace::Dmesg.status("fix0", "proposal rejected, #{file.to_s.split("/").last(2).join("/")}#{law ? " #{law}" : ""}: #{reason}")
          bus&.publish("repair_loop:proposal_rejected", law:, file:, reason: reason.to_s)
        end

        # A model call that produced nothing to judge: the model said UNCHANGED, sent an
        # empty reply, or sent a diff patch(1) refused. Counted apart from rejected
        # proposals and never against the file's two-reject limit, but named in the log,
        # because "no_proposal" alone said none of this.
        def declined(key, file:, law: nil, detail: nil)
          @mutex.synchronize { @declined[key.to_s] += 1 }
          where = file.to_s.split("/").last(2).join("/")
          Master::Trace::Dmesg.status("fix0", "no proposal, #{where}#{law ? " #{law}" : ""}: #{key}#{detail ? " (#{detail.to_s[0, 120]})" : ""}")
          nil
        end

        def declined_reasons = @mutex.synchronize { @declined.dup }

        # "patch_rejected 3, model_said_unchanged 2" for the heartbeat; nil when there is nothing to say.
        def why_line
          tally = reasons.merge(declined_reasons) { |_, a, b| a + b }
          return if tally.empty?

          tally.sort_by { |_, count| -count }.first(4).map { |reason, count| "#{reason} #{count}" }.join(", ")
        end

        def rejects_for(file) = @mutex.synchronize { @file_rejects[file.to_s] }

        # A file stops after two rejects: a third proposal costs a lane call and
        # has landed none of the first two.
        def file_done?(file) = rejects_for(file) >= MAX_REJECTS_PER_FILE

        def timeout(file, seconds)
          @mutex.synchronize { @timeouts << [file.to_s, seconds] }
        end

        def timeouts = @mutex.synchronize { @timeouts.dup }

        # A lane failing again and again is dropped for the run, so the next file
        # does not wait out the same failure. Returns true when this call dropped it.
        def lane_failed(model)
          lane = Master::Io::LaneQuota.lane_of(model)
          return false if lane.empty?

          count = @mutex.synchronize { @lane_failures[lane] += 1 }
          return false if count < LANE_FAILURES_BEFORE_DROP || Master::Io::LaneQuota.run_drops.key?(lane)

          Master::Io::LaneQuota.drop_for_run!(lane, "failed #{count} calls this run")
          Master::Trace::Dmesg.status("fix0", "lane #{lane} dropped for this run, #{count} failed calls")
          true
        end

        def reasons = @mutex.synchronize { @reasons.dup }

        # "rejected 14: new_violations 9, boyscout_violation 3, ..." for the summary.
        def summary_lines
          lines = []
          total = reasons.values.sum
          unless total.zero?
            parts = reasons.sort_by { |_, count| -count }.map { |reason, count| "#{reason} #{count}" }
            lines << "fix0: proposals rejected #{total}: #{parts.join(", ")}"
          end
          declined_total = declined_reasons.values.sum
          unless declined_total.zero?
            parts = declined_reasons.sort_by { |_, count| -count }.map { |reason, count| "#{reason} #{count}" }
            lines << "fix0: no proposal #{declined_total}: #{parts.join(", ")}"
          end
          lines << "fix0: file budget spent on #{timeouts.size} file(s): #{timeouts.first(5).map { |file, _| file.split("/").last }.join(", ")}" if timeouts.any?
          drops = Master::Io::LaneQuota.run_drops
          lines << "fix0: lanes dropped this run: #{drops.map { |lane, why| "#{lane} (#{why})" }.join(", ")}" if drops.any?
          lines
        end
      end
    end
  end
end
