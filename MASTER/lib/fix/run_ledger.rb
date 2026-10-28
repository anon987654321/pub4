# frozen_string_literal: true

module Master
  module Fix
    # What one /fix run has learned about its own model phase, kept in memory so
    # the rest of the run can act on it: why proposals were rejected (and how
    # often per file), which files ran out of wall-clock, and which lanes keep
    # failing. The 2026-10-12 runs fixed nothing and said only "0 fixed";
    # the reasons were in the log one line at a time and never added up.
    #
    # State is per run: RunBudget.begin_run clears it, because a long MASTER session runs /fix many
    # times in one process, and a file rejected twice in one run was excluded from every later one.
    module RunLedger
      MAX_REJECTS_PER_FILE = 2
      LANE_FAILURES_BEFORE_DROP = 2

      @mutex = Mutex.new
      @reasons = Hash.new(0)
      @declined = Hash.new(0)
      @file_rejects = Hash.new(0)
      @timeouts = []
      @lane_failures = Hash.new(0)
      @max_files = nil

      class << self
        def reset!
          begin_run!
          @mutex.synchronize { @max_files = nil }
        end

        # A new run's counters; the --max-files override set for this dispatch stays.
        def begin_run!
          @mutex.synchronize do
            @started_at = Time.now
            @reasons = Hash.new(0)
            @declined = Hash.new(0)
            @file_rejects = Hash.new(0)

            @timeouts = []
            @lane_failures = Hash.new(0)
          end
        end

        # Wall-clock seconds one file may spend in the model phase: a proposal, a retry when its patch
        # does not apply, and a verifier call, at the pinned lane's pace (data/limits.yml#fix_time).
        def file_budget_s = FixTime.file_s

        # --max-files N caps model repairs. Bounded runs retain early-stop
        # behavior unless MASTER_FIX_RANK=1 asks for full-scan impact ranking;
        # unbounded runs rank and cap each rolling batch before dispatch.
        def max_files
          @max_files || Integer(ENV.fetch("MASTER_FIX_MAX_FILES", "0"), exception: false).then { |n| n&.positive? ? n : nil }
        end

        # The command-line override is restored after a single /fix dispatch.
        def max_files_override = @max_files

        def restore_max_files_override(value)
          @max_files = value
        end

        def max_files=(value)
          @max_files = Integer(value).positive? ? Integer(value) : nil
        end

        # One proposal turned down: the reason, counted overall and against the file.
        # Counts only: every caller records the refusal through Refusals, which prints the line.
        def reject(reason, file:, law: nil, bus: nil)
          @mutex.synchronize do
            @reasons[reason.to_s] += 1
            @file_rejects[file.to_s] += 1
          end
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

        # The reason the last proposal on this thread was refused, kept so one retry can show
        # it to the model. Read once: a refusal feeds the next attempt only.
        def refused_because(text)
          Thread.current[:fix_refusal] = text.to_s.strip[0, 600]
          nil
        end

        def take_refusal
          Thread.current[:fix_refusal].tap { Thread.current[:fix_refusal] = nil }
        end

        # Runs the block with the refusal in the prompts built inside it.
        def retrying(note)
          Thread.current[:fix_retry_note] = note
          yield
        ensure
          Thread.current[:fix_retry_note] = nil
        end

        # The paragraph a prompt adds on a retry; empty on a first attempt.
        def retry_note
          note = Thread.current[:fix_retry_note]
          return "" if note.to_s.empty?

          "Your previous proposal was refused: #{note}\nMake a smaller change that avoids exactly that, touching only the lines the finding names."
        end

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
          lane = Master::Io::LaneState.lane_of(model)
          return false if lane.empty?

          count = @mutex.synchronize { @lane_failures[lane] += 1 }
          return false if count < LANE_FAILURES_BEFORE_DROP || Master::Io::LaneState.run_drops.key?(lane)

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
          drops = Master::Io::LaneState.run_drops
          lines << "fix0: lanes dropped this run: #{drops.map { |lane, why| "#{lane} (#{why})" }.join(", ")}" if drops.any?
          lines.concat(swallowed_lines)
        end

        # The errors the run caught and carried on past, by where they were caught. A verifier that
        # crashed on every diff, and a NoMethodError behind "offline", were found only by reading
        # swallowed_errors.jsonl by hand; the summary names them.
        def swallowed_lines
          return [] unless @started_at && defined?(Master::Ground::Swallow)

          rows = Master::Ground::Swallow.recent(limit: 5000, since: @started_at)
          return [] if rows.empty?

          by_place = rows.group_by { |row| row["context"] }.sort_by { |place| -place.last.size }
          ["fix0: errors swallowed this run #{rows.size} at #{by_place.size} place(s)"] +
            by_place.first(5).map { |place, group| swallowed_line(place, group) }
        end

        def swallowed_line(place, group)
          last = group.last
          "fix0: swallowed #{group.size}x at #{place}: #{last["error_class"]}: #{last["error_message"].to_s[0, 120]}"
        end
      end
    end

    # How long a /fix run, one file in it, and a quiet pass may take, read from
    # data/limits.yml#fix_time for the lane the run is pinned to. The numbers sat
    # in three constants tuned for free lanes that answer in seconds; every Opus
    # repair ran out of its 240 s, and each run needed three environment variables
    # to get the times the lane actually takes. MASTER_FIX_FILE_BUDGET_S,
    # MASTER_FIX_RUN_BUDGET_S and MASTER_FIX_STALL_S still override one run.
    module FixTime
      module_function

      # The variable that overrides each time for one run.
      KEYS = {
        file_s: "MASTER_FIX_FILE_BUDGET_S",
        run_s: "MASTER_FIX_RUN_BUDGET_S",
        stall_s: "MASTER_FIX_STALL_S",
      }.freeze

      def file_s(model: ENV["MASTER_MODEL"]) = seconds(:file_s, model)
      def run_s(model: ENV["MASTER_MODEL"]) = seconds(:run_s, model)
      def stall_s(model: ENV["MASTER_MODEL"]) = seconds(:stall_s, model)

      def seconds(key, model)
        override = Integer(ENV[KEYS.fetch(key)].to_s, exception: false)
        return override if override&.positive?

        lane = model.to_s.empty? ? nil : Master::Io::LaneState.lane_of(model)
        Integer(config.dig("lanes", lane, key.to_s) || config.fetch("default").fetch(key.to_s))
      end

      # Read on every call: a run is long and one file read is cheap next to a model call, and a cached
      # copy would make a test that writes its own limits depend on the order the suite ran in.
      def config
        data = Master.load_yaml(Master.limits_path, default: {}) || {}
        section = data["fix_time"]
        raise "data/limits.yml has no fix_time section" unless section.is_a?(Hash) && section["default"].is_a?(Hash)

        section
      end
    end
  end
end
