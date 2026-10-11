# frozen_string_literal: true

require "open3"
require "set"

module Master
  module Review
  # Compares public API surface across last N commits.
  # Reports methods, classes, modules present in HEAD~N but absent now.
    class CommitGuard
      DEFAULT_DEPTH = 3
      Omission = Data.define(:path, :name, :type, :last_seen_at)

      def initialize(root: Dir.pwd, depth: DEFAULT_DEPTH)
        @root = root
        @depth = depth
        @history_mutex = Mutex.new
      end

      def check(paths: nil)
        files = paths ? Array(paths).select { |f| f.end_with?(".rb") } : changed_rb_files
        return [] if files.empty?
        files.flat_map { |rel| check_file(rel) }.uniq { |o| [o.path, o.name] }
      end

      def render(omissions)
        return "commit_guard: no omissions detected" if omissions.empty?
        lines = omissions.map { |o| "  #{o.type} #{o.name} (was in #{o.last_seen_at}) — #{o.path}" }
        "commit_guard: #{omissions.size} omission(s)\n#{lines.join("\n")}"
      end

      private

      def check_file(rel)
        full = File.join(@root, rel)
        return [] unless File.exist?(full)
        return [] if unchanged_since_history?(rel, full)
        current = AstSignature.from_source(File.read(full))
        @depth.downto(1).flat_map do |n|
          hist = AstSignature.from_git(rel, ref: "HEAD~#{n}", root: @root)
          AstSignature.diff(hist, current).map do |s|
            Omission.new(path: rel, name: s.name, type: s.type, last_seen_at: "HEAD~#{n}")
          end
        end.uniq { |o| [o.path, o.name] }
      end

      # A file whose bytes match HEAD~1..HEAD~depth has no history signature the
      # working tree lacks, so the per-ref git show and parse are skipped. One
      # git diff per depth answers for every file; a file touched after that
      # answer was taken (mtime) goes through the full comparison.
      def unchanged_since_history?(rel, full)
        index = history_change_index
        return false unless index

        !index[:paths].include?(rel) && File.mtime(full) <= index[:taken_at]
      rescue SystemCallError
        false
      end

      def history_change_index
        @history_mutex.synchronize do
          @history_index = build_history_index unless defined?(@history_index)
          @history_index
        end
      end

      def build_history_index
        taken_at = Time.now
        paths = Set.new
        @depth.downto(1) do |n|
          out, st = Master::Io::Exec.capture2e("git", "diff", "--name-only", "--no-renames", "--relative", "HEAD~#{n}", chdir: @root)
          return nil unless st.success?

          out.each_line { |line| paths << line.chomp }
        end
        { paths:, taken_at: }
      end

      def changed_rb_files
        out, st = Master::Io::Exec.capture2e("git", "diff", "--name-only", "HEAD~#{@depth}..HEAD", "--", "*.rb", chdir: @root)
        return [] unless st.success?
        out.lines.map(&:strip).reject(&:empty?)
      end
    end
  end
end
