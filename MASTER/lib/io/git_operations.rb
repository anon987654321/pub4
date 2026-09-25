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
          Master::Ground::LawHandshake::Admission.require!
          scoped = Array(paths).map(&:to_s).reject(&:empty?)
          raise ArgumentError, "git commit needs paths: an unscoped commit takes the shared index" if scoped.empty?

          git!("add", "--", *scoped)
          git!("commit", "-m", message.to_s, "-m", Master::Core::World::COMMIT_TRAILER, "--", *scoped)
        end

        # A push since this checkout last fetched rejects ours, and the commit
        # stays local: /fix's first repair of MASTER sat unpushed while other
        # sessions pushed around it. Rebase onto what arrived and push once
        # more. A rebase that conflicts is aborted, and the refusal raised.
        def push
          git!("push", *push_target)
        rescue RuntimeError => e
          raise unless e.message.match?(/rejected|non-fast-forward|fetch first/)

          rebase_onto_upstream!
          git!("push", *push_target)
        end

        # The upstream named outright. A /fix worktree's branch is
        # agent/fix-<tree> tracking origin/main, and a bare push refuses a
        # branch whose name differs from its upstream's, so the delivery that
        # the proof had just cleared failed at the last step.
        def push_target
          upstream, status = Master::Io::Exec.capture2e("git", "-C", @root_path, "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}")
          remote, branch = upstream.to_s.strip.split("/", 2)
          return [] unless status.success? && remote && branch

          [remote, "HEAD:#{branch}"]
        end

        def rebase_onto_upstream!
          git!("pull", "--rebase", "--autostash")
        rescue RuntimeError
          Master::Io::Exec.capture2e("git", "-C", @root_path, "rebase", "--abort")
          raise
        end

        def git!(*args)
          Master::Ground::LawHandshake::Admission.require!
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

      # Reading what changed: the commits between two points, the patch
      # between them, and the patch not yet committed. A repair pass shows all
      # three, which is the only reason they exist.
      module History
        def log_between(from, to = "HEAD")
          out, _, st = Master::Io::Exec.capture3("git", "-C", @root_path, "log", "--oneline", "#{from}..#{to}")
          st.success? ? out.strip.lines.map(&:chomp) : []
        end

        def patch_between(from, to = "HEAD", limit: 400)
          out, _, st = Master::Io::Exec.capture3("git", "-C", @root_path, "diff", "#{from}..#{to}")
          return "" unless st.success?

          lines = out.lines
          return out if lines.size <= limit

          "#{lines.first(limit).join}… #{lines.size - limit} more lines of patch\n"
        end

        def working_patch(limit: 400)
          out, _, st = Master::Io::Exec.capture3("git", "-C", @root_path, "diff")
          return "" unless st.success?

          lines = out.lines
          lines.size <= limit ? out : "#{lines.first(limit).join}… #{lines.size - limit} more lines of patch\n"
        end
      end

      include Mutations
      include History

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

      # What a range of commits did, for a report that would otherwise say a
      # repair happened and show nothing of it.
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
