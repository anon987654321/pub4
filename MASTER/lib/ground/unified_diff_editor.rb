# frozen_string_literal: true

module Master
  module Ground
    class UnifiedDiffEditor
      HUNK_RE = /^@@\s+-(\d+)(?:,(\d+))?\s+\+(\d+)(?:,(\d+))?\s+@@/.freeze

      def initialize(root: Master::ROOT)
        @root = root
      end

      def parse(diff)
        files = []
        current = nil
        diff.to_s.each_line { |line| current = consume_line(line, current, files) }
        files
      end

      def applyable?(diff)
        files = parse(diff)
        files.any? && files.all? do |file|
          path = file[:new] || file[:old]
          !Master::Ground::Immutability.blocked?(path, root: @root) && File.file?(abs(path))
        end
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "unified_diff_editor.applyable")
        false
      end

      def summary(diff)
        parse(diff).map do |file|
          adds = count_changes(file, "+", "+++")
          dels = count_changes(file, "-", "---")
          "#{file[:new] || file[:old]} +#{adds} -#{dels} hunks=#{file[:hunks].size}"
        end
      end

      def build_single_file(path:, before:, after:, context: 3)
        before_lines = before.to_s.lines
        after_lines = after.to_s.lines
        return "" if before_lines == after_lines

        [
          "--- #{path}\n",
          "+++ #{path}\n",
          "@@ -1,#{before_lines.size} +1,#{after_lines.size} @@\n",
        *diff_lines(before_lines, after_lines, _context: context),
        ].join
      end

      private

      def consume_line(line, current, files)
        handler, match = line_handler(line)
        send(handler, line, match, current, files)
      end

      def line_handler(line)
        return [:consume_old_header, Regexp.last_match] if line.match(/^---\s+(.+)/)
        return [:consume_new_header, Regexp.last_match] if line.match(/^\+\+\+\s+(.+)/)
        return [:consume_hunk_header, Regexp.last_match] if line.match(HUNK_RE)

        [:consume_hunk_line, nil]
      end

      def consume_old_header(_line, match, _current, files)
        current = { old: clean_path(match[1]), new: nil, hunks: [] }
        files << current
        current
      end

      def consume_new_header(_line, match, current, _files)
        current[:new] = clean_path(match[1]) if current
        current
      end

      def consume_hunk_header(_line, match, current, _files)
        raise ArgumentError, "hunk without file" unless current

        current[:hunks] << hunk(match)
        current
      end

      def consume_hunk_line(line, _match, current, _files)
        current[:hunks].last[:lines] << line if current && current[:hunks].any?
        current
      end

      def hunk(match)
        {
          old_start: match[1].to_i,
          old_count: (match[2] || "1").to_i,
          new_start: match[3].to_i,
          new_count: (match[4] || "1").to_i,
          lines: [],
        }
      end

      def count_changes(file, prefix, header)
        file[:hunks].sum { |item| item[:lines].count { |line| line.start_with?(prefix) && !line.start_with?(header) } }
      end

      def diff_lines(before, after, _context: 3)
        prefix = 0
        max = [before.size, after.size].max
        lines = []
        max.times do |idx|
          old = before[idx]
          new = after[idx]
          if old == new
            lines << " #{old}" if old
          else
            lines << "-#{old}" if old
            lines << "+#{new}" if new
          end
          prefix += 1
        end
        lines
      end

      def clean_path(path)
        path.to_s.sub(%r{\A[ab]/}, "").strip
      end

      def abs(path)
        full = File.expand_path(path.to_s, @root)
        raise ArgumentError, "diff path escapes root: #{path}" unless full.start_with?(@root + File::SEPARATOR)

        full
      end
    end
  end
end
