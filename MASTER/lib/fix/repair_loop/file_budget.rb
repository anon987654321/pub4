# frozen_string_literal: true

require "timeout"

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
          Master::Trace::Dmesg.status("fix0", "#{violation[:file].to_s.delete_prefix("#{@root}/")} skipped, #{RunLedger.file_budget_s}s file budget spent")
          nil
        end

        # The lines each finding of this repair points at.
        def scope_lines(violation) = [violation[:line].to_i]

        # nil when every changed hunk lies within SCOPE_PAD of a finding, or is a
        # small edit at a call of a method defined in that range, else a sentence
        # saying where. A finding with no line (a whole-file rule) leaves the
        # proposal unchecked.

        # Hunks, not one first-to-last span: changing a method's signature
        # (FEW_ARGUMENTS) means editing its callers, which sit anywhere in the
        # file. Judged as one span, every such repair read as a rewrite of the
        # lines between and was refused, and the model's only in-scope answer was
        # to hide the arguments behind a splat.
        def outside_finding_range(violation, proposed_src)
          lines = scope_lines(violation).select(&:positive?)
          return if lines.empty? || !File.file?(violation[:file].to_s)

          range = (lines.min - SCOPE_PAD)..(lines.max + SCOPE_PAD)
          stray = stray_hunks(File.read(violation[:file], encoding: "UTF-8"), proposed_src, range)
          return if stray.empty?

          "changes lines #{stray.map(&:first).min}-#{stray.map(&:last).max}, " \
            "finding range is #{[range.begin, 1].max}-#{range.end}"
        end

        def stray_hunks(old_src, new_src, range)
          callees = methods_defined_in(old_src.lines, range)
          changed_hunks(old_src, new_src).reject { |hunk| hunk_in_scope?(hunk, range:, callees:) }
        end

        CALL_SITE_HUNK_MAX = 4

        # first..last in the old file; new_first..new_last where it landed in the proposal.
        Hunk = Struct.new(:first, :last, :text, :size, :new_first, :new_last, keyword_init: true)

        def hunk_in_scope?(hunk, range:, callees:)
          return true if range.cover?(hunk.first) && range.cover?(hunk.last)
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

        # Each changed region of the old file, from git's own diff; one span
        # when git cannot say.
        def changed_hunks(old_src, new_src)
          git_hunks(old_src, new_src) || span_hunk(old_src, new_src)
        end

        def span_hunk(old_src, new_src)
          first, last = changed_old_region(old_src, new_src)
          return [] unless first

          [Hunk.new(first:, last:, text: old_src.lines[(first - 1)..(last - 1)].to_a.join, size: last - first + 1)]
        end

        def git_hunks(old_src, new_src)
          Dir.mktmpdir("fix-scope") do |dir|
            before = File.join(dir, "before")
            after = File.join(dir, "after")
            File.write(before, old_src)
            File.write(after, new_src)

            out, status = Master::Io::Exec.capture2e("git", "diff", "--no-index", "-U0", "--no-color", before, after)
            return nil unless [0, 1].include?(status.exitstatus)

            sides = { old: old_src.lines, new: new_src.lines }
            out.scan(/^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@/).map { |header| hunk_from(header, sides) }
          end
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "RepairLoop.git_hunks")
          nil
        end

        # One @@ header: the old span it replaces and the text on both sides.
        def hunk_from(header, sides)
          old_first, old_count, new_first, new_count =
            header.zip(%w[0 1 0 1]).map { |value, default| (value || default).to_i }
          text = (sides[:old][(old_first - 1), old_count].to_a + sides[:new][(new_first - 1), new_count].to_a).join
          last = old_count.zero? ? old_first : old_first + old_count - 1
          new_last = new_count.zero? ? new_first : new_first + new_count - 1
          Hunk.new(first: old_first, last:, text:, size: [old_count, new_count].max, new_first:, new_last:)
        end

        # The proposal's changed lines, hunk by hunk: a signature change edits its callers across
        # the file, and one first-to-last span charged it with every finding in between.
        def changed_new_ranges(old_src, new_src)
          hunks = git_hunks(old_src, new_src)
          return [Range.new(*changed_region(old_src, new_src))] unless hunks

          hunks.map { |hunk| hunk.new_first..hunk.new_last }
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
