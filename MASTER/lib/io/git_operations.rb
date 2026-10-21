# frozen_string_literal: true

require "open3"
require "tempfile"
require "pathname"

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
          scoped = scoped_paths(paths)
          raise ArgumentError, "git commit needs paths: an unscoped commit takes the shared index" if scoped.empty?

          commit_message = normalize_commit_message(message)
          with_pathspec_file(scoped) do |pathspec_file|
            git!("add", "--pathspec-from-file=#{pathspec_file}", "--pathspec-file-nul")
            git!("commit", "-m", commit_message, "-m", Master::Core::World::COMMIT_TRAILER,
                 "--pathspec-from-file=#{pathspec_file}", "--pathspec-file-nul")
          end
        end

        def normalize_commit_message(message)
          text = message.to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
          lines = text.gsub("\r\n", "\n").gsub("\r", "\n").strip.split("\n")
          title = Master::Ground::CommitFormat.normalize_subject(lines.shift)
          raise ArgumentError, "git commit needs a non-empty subject" if title.empty?
          raise ArgumentError, "git commit subject exceeds #{Master::Ground::CommitFormat.max_chars} characters" if title.length > Master::Ground::CommitFormat.max_chars

          body = lines.join("\n").strip
          [title, body].reject(&:empty?).join("\n\n")
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
          st.success? ? from_git(out).strip.lines.map(&:chomp) : []
        end

        def patch_between(from, to = "HEAD", limit: 400)
          out, _, st = Master::Io::Exec.capture3("git", "-C", @root_path, "diff", "#{from}..#{to}")
          return "" unless st.success?

          out = from_git(out)
          lines = out.lines
          return out if lines.size <= limit

          "#{lines.first(limit).join}… #{lines.size - limit} more lines of patch\n"
        end

        # Every path that differs from a commit, committed, edited or new, relative to
        # this root. A path that differs from the commit before the run may have been
        # written by the run, so the list errs wide, never narrow.
        def paths_since(from)
          tracked, _diff_err, found = Master::Io::Exec.capture3(
            "git", "-C", @root_path, "diff", "--name-only", "--relative", "-z", from, "--", "."
          )

          fresh, _list_err, listed = Master::Io::Exec.capture3(
            "git", "-C", @root_path, "ls-files", "--others", "--exclude-standard", "-z", "--", "."
          )
          return unless found.success? && listed.success?

          (tracked.split("\0") + fresh.split("\0")).reject(&:empty?).uniq
        end

        def working_patch(limit: 400)
          out, _, st = Master::Io::Exec.capture3("git", "-C", @root_path, "diff")
          return "" unless st.success?

          out = from_git(out)
          lines = out.lines
          lines.size <= limit ? out : "#{lines.first(limit).join}… #{lines.size - limit} more lines of patch\n"
        end

        private

        # git writes bytes. A pipe read comes back tagged binary, and a binary string raises when it is
        # joined to the ellipsis above or to any other UTF-8 text.
        def from_git(text) = text.dup.force_encoding(Encoding::UTF_8).scrub
      end

      include Mutations
      include History

      private

      def scoped_paths(paths)
        Array(paths).map(&:to_s).reject(&:empty?).map do |path|
          raise ArgumentError, "git path must be relative to the runtime root: #{path.inspect}" if Pathname.new(path).absolute?

          segments = path.split("/")
          raise ArgumentError, "git path escapes the runtime root: #{path.inspect}" if segments.include?("..")

          path
        end.uniq
      end

      def with_pathspec_file(paths)
        file = Tempfile.new(["master-git-paths-", ".nul"])
        file.binmode
        file.write(paths.join("\x00"))
        file.write("\x00")
        file.close
        yield file.path
      ensure
        file&.close!
      end

      def repository_prefix
        output, status = Master::Io::Exec.capture2e("git", "-C", @root_path, "rev-parse", "--show-prefix")
        status.success? ? output.to_s.strip : ""
      end

      def parse_status_paths(output)
        records = output.to_s.split("\x00")
        paths = []
        index = 0
        while index < records.length
          record = records[index]
          index += 1
          next if record.to_s.empty? || record.length < 4

          paths << record[3..]
          index += 1 if record.start_with?("R") || record.start_with?("C")
        end
        paths.uniq
      end

      public

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
        out, _, status = Master::Io::Exec.capture3(
          "git", "-C", @root_path, "status", "--porcelain=v1", "-z", "--untracked-files=all", "--", "."
        )
        return [] unless status.success?

        prefix = repository_prefix
        parse_status_paths(out).map { |path| path.delete_prefix(prefix).delete_prefix("/") }.uniq
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
