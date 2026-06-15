# frozen_string_literal: true

module Master
  module Ground
    class UnifiedDiffEditor
      HUNK_RE = /^@@\s+-(\d+)(?:,(\d+))?\s+\+(\d+)(?:,(\d+))?\s+@@/.freeze

      def initialize(root: Master::ROOT)
        @root = root
      end

      def parse(diff)
        current = nil
        files = []
        diff.to_s.each_line do |line|
          case line
          when /^---\s+(.+)/
            current = { old: clean_path(Regexp.last_match(1)), new: nil, hunks: [] }
            files << current
          when /^\+\+\+\s+(.+)/
            current[:new] = clean_path(Regexp.last_match(1)) if current
          when HUNK_RE
            raise ArgumentError, "hunk without file" unless current
          else
            current[:hunks].last[:lines] << line if current && current[:hunks].any?
          end
        end
        files
      end

      def applyable?(diff)
        parse(diff).all? { |file| File.file?(abs(file[:new] || file[:old])) }
      rescue StandardError
        false
      end

      def summary(diff)
        parse(diff).map do |file|
          adds = file[:hunks].sum { |h| h[:lines].count { |line| line.start_with?("+") && !line.start_with?("+++") } }
          dels = file[:hunks].sum { |h| h[:lines].count { |line| line.start_with?("-") && !line.start_with?("---") } }
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
          *diff_lines(before_lines, after_lines),
        ].join
      end

      private

      def diff_lines(before, after)
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
        File.join(@root, path.to_s)
      end
    end
  end
end
