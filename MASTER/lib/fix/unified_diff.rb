# frozen_string_literal: true

require "tmpdir"
require_relative "../io/exec"
require_relative "../ground/swallow"

module Master
  module Fix

    # git's own unified diff, parsed into hunks. ChangeScope reads one repair
    # through it, and the pre-commit lint a whole commit.
    module UnifiedDiff
      # Lines are 1-based. A hunk that only inserts sits at the old line it
      # follows, one that only deletes at the new line it follows, as git's -U0
      # headers number them.
      Hunk = Data.define(:old_first, :old_count, :new_first, :new_count, :text) do
        def old_range = old_first..[old_first + old_count - 1, old_first].max

        def new_range = new_first..[new_first + new_count - 1, new_first].max

        def size = [old_count, new_count].max
      end

      HEADER = /\A@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@/
      FILE_START = /\Adiff --git /
      # --text: a NUL or an invalid byte otherwise makes "Binary files differ" and no hunks.
      GIT_DIFF = %w[git -c core.autocrlf=false diff --no-index --no-ext-diff --no-color --text].freeze

      class << self
        # git's diff of two sources, as UTF-8, or nil when git cannot say.
        def between(old_src, new_src, context: 0)
          Dir.mktmpdir("unified-diff") do |dir|
            before = write(dir, name: "before", src: old_src)
            after = write(dir, name: "after", src: new_src)
            out, status = Master::Io::Exec.capture2e(*GIT_DIFF, "-U#{Integer(context)}", before, after)

            [0, 1].include?(status&.exitstatus) ? readable(out) : nil
          end
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "UnifiedDiff.between")
          nil
        end

        # The hunks of one file's diff; a hunk's text is both sides' changed
        # lines without their marks.
        def hunks(diff)
          readable(diff).each_line.slice_before(HEADER).filter_map do |lines|
            header = lines.first.match(HEADER)
            next unless header

            changed = lines.drop(1).select { |line| line.start_with?("-", "+") }
            hunk(header, changed.map { |line| line[1..] }.join)
          end
        end

        # Each file's diff body in a multi-file diff, keyed by its path after
        # "+++ b/"; a deleted file has no new side and no entry. An added line
        # reading "++ x" arrives as "+++ x", so only a file's header names it.
        def per_file(text)
          readable(text).each_line.slice_before(FILE_START).each_with_object({}) do |lines, files|
            start = lines.index { |line| line.start_with?("@@") } || lines.size

            path = new_path(lines.first(start))
            files[path] = lines.drop(start).join if path
          end
        end

        # When git cannot diff: the common prefix and suffix trimmed, and the
        # rest one hunk.
        def span(old_src, new_src)
          sides = [old_src.lines, new_src.lines]
          prefix = common_prefix(*sides)
          suffix = common_prefix(*sides.map { |lines| lines.drop(prefix).reverse })

          span_hunk(*sides.map { |lines| lines[prefix...(lines.size - suffix)] }, after: prefix)
        end

        private

        def write(dir, name:, src:)
          File.join(dir, name).tap { |path| File.binwrite(path, src) }
        end

        def hunk(header, text)
          old_first, old_count, new_first, new_count =
            header.captures.zip(%w[0 1 0 1]).map { |value, default| (value || default).to_i }
          Hunk.new(old_first:, old_count:, new_first:, new_count:, text:)
        end

        # The lines between the common prefix and suffix, numbered as git
        # numbers a hunk: an empty side sits at the line it follows.
        def span_hunk(removed, added, after:)
          Hunk.new(old_first: removed.empty? ? after : after + 1, old_count: removed.size,
                   new_first: added.empty? ? after : after + 1, new_count: added.size, text: (removed + added).join)
        end

        def new_path(header)
          named = header.find { |line| line.start_with?("+++ ") }.to_s.chomp.delete_prefix("+++ ")
          named.delete_prefix("b/") unless named.empty? || named == "/dev/null"
        end

        def common_prefix(left, right) = left.zip(right).take_while { |pair| pair.first == pair.last }.size

        # git's bytes are BINARY; a source with non-UTF-8 bytes still has hunks
        # to count, so its text is scrubbed rather than refused.
        def readable(text) = text.to_s.dup.force_encoding(Encoding::UTF_8).scrub
      end
    end
  end
end
