# frozen_string_literal: true

require "timeout"
require_relative "../change_scope"

module Master
  module Fix
    class RepairLoop
      # Two bounds on what one proposal may cost: the wall-clock a file gets for
      # its model calls (RunLedger.file_budget_s, 240 s by default), and the lines
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
          refuse(:budget, violation, reason: "skipped, #{RunLedger.file_budget_s}s file budget spent")
          nil
        end

        # The lines each finding of this repair points at.
        def scope_lines(violation) = [violation[:line].to_i]

        # nil when every changed hunk lies within SCOPE_PAD of a finding, or is a
        # small edit at a call of a method defined in that range, else a sentence
        # saying where. A finding with no line (a whole-file rule) leaves the
        # proposal unchecked.
        #
        # Hunks, not one first-to-last span: changing a method's signature
        # (FEW_ARGUMENTS) means editing its callers, which sit anywhere in the
        # file. Judged as one span, every such repair read as a rewrite of the
        # lines between and was refused, and the model's only in-scope answer was
        # to hide the arguments behind a splat.
        def outside_finding_range(violation, proposed_src)
          lines = scope_lines(violation).select(&:positive?)
          return if lines.empty? || !File.file?(violation[:file].to_s)

          range = (lines.min - SCOPE_PAD)..(lines.max + SCOPE_PAD)
          old_src = File.read(violation[:file], encoding: "UTF-8")
          callees = methods_defined_in(old_src.lines, range)
          hunks = ChangeScope.between(old_src, proposed_src).hunks
          stray = hunks.reject { |hunk| hunk_in_scope?(hunk, range:, callees:) }.map(&:old_range)
          return if stray.empty?

          "changes lines #{stray.map(&:begin).min}-#{stray.map(&:end).max}, " \
            "finding range is #{[range.begin, 1].max}-#{range.end}"
        end

        CALL_SITE_HUNK_MAX = 4

        def hunk_in_scope?(hunk, range:, callees:)
          return true if range.cover?(hunk.old_range.begin) && range.cover?(hunk.old_range.end)
          return false if hunk.size > CALL_SITE_HUNK_MAX

          callees.any? { |name| hunk.text.match?(/(?<![\w@$])#{Regexp.escape(name)}(?!\w)/) }
        end

        # Methods whose def sits in the finding's range: their call sites may
        # change with them. Short or generic names would match too much.
        def methods_defined_in(old_lines, range)
          old_lines[[range.begin - 1, 0].max..(range.end - 1)].to_a
            .filter_map { |line| line[/\bdef\s+(?:self\.)?([a-z_]\w*[?!=]?)/, 1] }
            .reject { |name| name.length < 4 || %w[call initialize].include?(name) }
            .uniq
        end
      end
    end
  end
end
