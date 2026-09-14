# frozen_string_literal: true

require "open3"

module Master
  module Io
    # GitOperations — git wrappers scoped to a repository root.
    class GitOperations
      # State-changing git commands (add/commit/push/reset/tag/fetch) — kept
      # separate from GitOperations' own read-only status/inspection queries.
      module Mutations
        # Stages and commits the named paths and nothing else, the rule
        # Core::World#do_git_commit keeps for the fold. The index is shared with
        # every session in this checkout, so committing it signs their staged
        # work with this message. A refused add or commit raises: a pre-commit
        # hook that said no used to read as a commit.
        def commit(message, paths:)
          scoped = Array(paths).map(&:to_s).reject(&:empty?)
          raise ArgumentError, "git commit needs paths: an unscoped commit takes the shared index" if scoped.empty?

          git!("add", "--", *scoped)
          git!("commit", "-m", message.to_s, "-m", Master::Core::World::COMMIT_TRAILER, "--", *scoped)
        end

        def push = git!("push")

        def git!(*args)
          output, status = Master::Io::Exec.capture2e("git", "-C", @root_path, *args)
          raise "git #{args.first} failed: #{output.strip}" unless status.success?

          output
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

      # Modified and untracked paths under the root, relative to it. Porcelain
      # status names paths from the top of the repository, which is not this
      # root when the runtime lives in a subdirectory of the checkout, as
      # MASTER does in pub4.
      def changed_paths
        out, _, status = Master::Io::Exec.capture3("git", "-C", @root_path, "ls-files", "--modified", "--others",
                                                   "--exclude-standard")
        status.success? ? out.lines.map(&:chomp).uniq : []
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
