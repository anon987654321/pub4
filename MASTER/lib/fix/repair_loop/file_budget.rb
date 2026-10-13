# frozen_string_literal: true

require "timeout"

module Master
  module Fix
    class RepairLoop
      # Two bounds on what one proposal may cost: the wall-clock a file gets for
      # its model calls (RunLedger.file_budget_s, 90 s by default), and the lines
      # a fix may touch (the finding's own line plus a margin). A file that runs
      # out of time is skipped and recorded, never waited out; a proposal that
      # rewrites lines no finding names is refused before the verifier is asked.
      module FileBudget
        SCOPE_PAD = 25

        private

        def start_file_budget
          @file_timed_out = false
          @file_deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + RunLedger.file_budget_s
        end

        # Runs the block inside what is left of the file's budget. A timeout
        # returns nil with @file_timed_out set and the file is recorded. The lane
        # is not charged: a slow call on a large file says nothing about the lane, and
        # two of them used to drop the pinned model for a free one.
        def within_file_budget(violation)
          remaining = @file_deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
          raise Timeout::Error, "file budget spent" if remaining <= 0

          Timeout.timeout(remaining) { yield }
        rescue Timeout::Error
          @file_timed_out = true
          RunLedger.timeout(violation[:file], RunLedger.file_budget_s)
          @bus&.publish("repair_loop:file_timeout", law: @law.id, file: violation[:file], seconds: RunLedger.file_budget_s)
          Master::Trace::Dmesg.status("fix0", "#{violation[:file].to_s.delete_prefix("#{@root}/")} skipped, #{RunLedger.file_budget_s}s file budget spent")
          nil
        end

        # The lines each finding of this repair points at.
        def scope_lines(violation) = [violation[:line].to_i]

        # nil when every changed line lies within SCOPE_PAD of a finding, else a
        # sentence saying where. A finding with no line (a whole-file rule)
        # leaves the proposal unchecked.
        def outside_finding_range(violation, proposed_src)
          lines = scope_lines(violation).select(&:positive?)
          return if lines.empty? || !File.file?(violation[:file].to_s)

          old_src = File.read(violation[:file], encoding: "UTF-8")
          first, last = changed_old_region(old_src, proposed_src)
          return unless first

          low = lines.min - SCOPE_PAD
          high = lines.max + SCOPE_PAD
          return if first >= low && last <= high

          "changes lines #{first}-#{last}, finding range is #{[low, 1].max}-#{high}"
        end

        # The 1-based span of the OLD file that differs from the proposal, or nil
        # when nothing differs. An insertion is the one line it lands before.
        def changed_old_region(old_src, new_src)
          old_lines = old_src.lines
          new_lines = new_src.lines
          prefix = 0
          prefix += 1 while prefix < old_lines.size && prefix < new_lines.size && old_lines[prefix] == new_lines[prefix]
          return if prefix == old_lines.size && prefix == new_lines.size

          limit = [old_lines.size, new_lines.size].min - prefix
          suffix = 0
          suffix += 1 while suffix < limit && old_lines[old_lines.size - 1 - suffix] == new_lines[new_lines.size - 1 - suffix]
          first = prefix + 1
          [first, [old_lines.size - suffix, first].max]
        end
      end
    end
  end
end
