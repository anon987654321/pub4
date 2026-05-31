# frozen_string_literal: true

require "open3"

module Master
  module Judge
  # Compares public API surface across last N commits.
  # Reports methods, classes, modules present in HEAD~N but absent now.
    class CommitGuard
      DEFAULT_DEPTH = 3
      Omission = Data.define(:path, :name, :type, :last_seen_at)

      def initialize(root: Dir.pwd, depth: DEFAULT_DEPTH)
        @root = root
        @depth = depth
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
        current = AstSignature.from_source(File.read(full))
        @depth.downto(1).flat_map { |n|
          hist = AstSignature.from_git(rel, ref: "HEAD~#{n}", root: @root)
          AstSignature.diff(hist, current).map { |s|
            Omission.new(path: rel, name: s.name, type: s.type, last_seen_at: "HEAD~#{n}")
          }
        }.uniq { |o| [o.path, o.name] }
      end

      def changed_rb_files
        out, st = Open3.capture2e("git", "diff", "--name-only", "HEAD~#{@depth}..HEAD", "--", "*.rb", chdir: @root)
        return [] unless st.success?
        out.lines.map(&:strip).reject(&:empty?)
      end
    end
  end
end
