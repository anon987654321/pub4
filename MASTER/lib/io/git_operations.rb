# frozen_string_literal: true

require "open3"


# ---- merged from lib/io/git_operations/mutations.rb (one-file directory collapse, 2026-08-19) ----
module Master
  module Io
    class GitOperations
      # State-changing git commands (add/commit/push/reset/tag/fetch) — kept
      # separate from GitOperations' own read-only status/inspection queries.
      module Mutations
        def add_all
          Master::Io::Exec.capture2e("git", "-C", @root_path, "add", "-A")
        end

        def commit(message)
          Master::Io::Exec.capture2e("git", "-C", @root_path, "commit", "-m", message.to_s)
        end

        def push
          Master::Io::Exec.capture2e("git", "-C", @root_path, "push")
        end

        def reset_hard(ref = "origin/main")
          Master::Io::Exec.capture2e("git", "-C", @root_path, "reset", "--hard", ref)
        end

        def tag(name)
          Master::Io::Exec.capture2e("git", "-C", @root_path, "tag", name)
        end

        def fetch
          Master::Io::Exec.capture2e("git", "-C", @root_path, "fetch")
        end
      end
    end
  end
end

module Master
  module Io
    # GitOperations — git wrappers scoped to a repository root.
    class GitOperations
      include Mutations

      def initialize(root_path)
        @root_path = root_path
      end

      def dirty?(path = "lib/")
        !status_lines(path).empty?
      end

      def status_lines(path = nil)
        args = ["git", "-C", @root_path, "status", "--porcelain"]
        args << path if path
        out, = Master::Io::Exec.capture2e(*args)
        out.lines.map(&:chomp)
      end

      def dirty_count(path = nil)
        status_lines(path).size
      end

      def ahead_behind
        out, _, st = Master::Io::Exec.capture3(
          "git", "-C", @root_path, "rev-list", "--left-right", "--count", "HEAD...@{u}"
        )
        return [0, 0] unless st.success?
        a, b = out.strip.split.map(&:to_i)
        [a || 0, b || 0]
      end

      def diff_stat(base = "HEAD")
        out, = Master::Io::Exec.capture2e("git", "-C", @root_path, "diff", base, "--stat")
        out.strip
      end

      def head
        out, _, st = Master::Io::Exec.capture3("git", "-C", @root_path, "rev-parse", "--short", "HEAD")
        st.success? ? out.strip : nil
      end

      def branch
        out, _, st = Master::Io::Exec.capture3("git", "-C", @root_path, "rev-parse", "--abbrev-ref", "HEAD")
        st.success? ? out.strip : nil
      end
    end
  end
end
