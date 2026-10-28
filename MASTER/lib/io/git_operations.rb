# frozen_string_literal: true

require "open3"
require "tempfile"
require "pathname"

module Master
  module Io
    # GitOperations — git wrappers scoped to a repository root.
    class GitOperations
      # A person's yes, typed at a terminal, to committing these sacred paths once. It is the
      # guard's one exception, so `soul approve` commits through the same door as every other
      # writer instead of beside it. Only `confirm_at_terminal` should make one; nothing
      # automated has a terminal to answer.
      OperatorConfirmation = Data.define(:paths)

      def self.confirm_at_terminal(paths, input: $stdin, output: $stdout)
        return unless input.tty?

        output.print "commit #{paths.join(", ")}, which automation may not write? [y/N] "
        input.gets.to_s.strip.casecmp?("y") ? OperatorConfirmation.new(paths: paths.map(&:to_s).freeze) : nil
      end

      # State-changing git commands (add, commit, push, the rebase a rejected push
      # needs), kept apart from the read-only status and inspection queries.
      module Mutations
        # Stages and commits the named paths and nothing else, the rule
        # Core::World#do_git_commit keeps for the fold. The index is shared with
        # every session in this checkout, so committing it signs their staged
        # work with this message. A refused add or commit raises: a pre-commit
        # hook that said no used to read as a commit.
        def commit(message, paths:, confirmed: nil)
          Master::Ground::LawHandshake::Admission.require!
          scoped = scoped_paths(paths)
          raise ArgumentError, "git commit needs paths: an unscoped commit takes the shared index" if scoped.empty?

          commit_message = normalize_commit_message(message)
          # Refused before the add, so a refusal leaves nothing staged in the shared index.
          refuse_sacred!(["commit", "--", *scoped], confirmed:)
          with_pathspec_file(scoped) do |pathspec_file|
            git!("add", "--pathspec-from-file=#{pathspec_file}", "--pathspec-file-nul")
            git!("commit", "-m", commit_message, "-m", Master::Core::World::COMMIT_TRAILER,
                 "--pathspec-from-file=#{pathspec_file}", "--pathspec-file-nul", confirmed:)
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

          rebase_onto_push_target!
          git!("push", *push_target)
        end

        # Publish this branch's name, never the branch it happens to track.
        # A repair worktree can intentionally track origin/main for comparisons,
        # but its checkpoints must create/update origin/work/<name> rather than
        # quietly pushing every intermediate repair straight to main. A branch
        # without an upstream is a normal first-push case, not permission to use
        # Git's implicit push.default behavior.
        def push_target
          branch_out, branch_status = Master::Io::Exec.capture2e(
            "git", "-C", @root_path, "symbolic-ref", "--quiet", "--short", "HEAD"
          )
          branch = branch_out.to_s.strip
          raise "git push refused: checkout has no named branch" unless branch_status.success? && !branch.empty?

          remotes_out, remotes_status = Master::Io::Exec.capture2e("git", "-C", @root_path, "remote")
          remotes = remotes_status.success? ? remotes_out.lines.map(&:strip).reject(&:empty?) : []
          raise "git push refused: no configured remote" if remotes.empty?

          config = lambda do |key|
            value, status = Master::Io::Exec.capture2e("git", "-C", @root_path, "config", "--get", key)
            status.success? ? value.to_s.strip : nil
          end
          branch_push_remote = config.call("branch.#{branch}.pushRemote")
          default_push_remote = config.call("remote.pushDefault")
          [branch_push_remote, default_push_remote].compact.each do |remote|
            raise "git push refused: configured push remote #{remote.inspect} does not exist" unless remotes.include?(remote)
          end
          branch_remote = config.call("branch.#{branch}.remote")
          remote = branch_push_remote || default_push_remote ||
            (branch_remote if remotes.include?(branch_remote)) ||
            ("origin" if remotes.include?("origin")) || remotes.first

          [remote, "HEAD:#{branch}"]
        end

        # If a fast-forward-only push loses a race, fetch and rebase onto the
        # remote counterpart of this branch—not @{u}, which may deliberately be
        # origin/main for a topic branch. Dirty unrelated files remain protected
        # by Git's autostash.
        def rebase_onto_push_target!
          remote, target = push_target
          branch = target.delete_prefix("HEAD:")
          git!("fetch", remote, branch)
          git!("rebase", "--autostash", "FETCH_HEAD")
        rescue RuntimeError
          Master::Io::Exec.capture2e("git", "-C", @root_path, "rebase", "--abort")
          raise
        end

        # Every write passes here, under the receipt the Fold's tool calls carry: a
        # durable before-event or no git, then an after-event with the outcome. The
        # receipt holds a digest of the arguments, never the message or the paths.
        def git!(*args, confirmed: nil)
          Master::Ground::LawHandshake::Admission.require!
          refuse_sacred!(args, confirmed:) if args.first == "commit"
          receipt = receipts.before(tool: "git_#{args.first}", tier: "dangerous", args:)
          started = Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond)
          output, status = run_receipted(receipt, args, started)
          raise "git #{args.first} failed: #{output.strip}" unless status.success?

          output
        end

        def run_receipted(receipt, args, started)
          output, status = Master::Io::Exec.capture2e("git", "-C", @root_path, *args)
          close_receipt(receipt, args, started, status.success? ? "success" : "error")
          [output, status]
        rescue StandardError
          close_receipt(receipt, args, started, "unknown_outcome")
          raise
        end

        def close_receipt(receipt, args, started, outcome)
          elapsed_ms = Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond) - started
          receipts.after(identity: receipt, tool: receipt.tool, tier: receipt.tier, args:, status: outcome, elapsed_ms:)
        end

        def receipts = @receipts ||= Master::Trace::ToolObserver.new(bus: Master::Trace::EventBus.new)

        # Every runtime commit passes here: the fix loop's, a restructure's, a rename's, the
        # proof's delivery, a standing order's, /commit's and a design run's. So this is the
        # one place a sacred path is refused, whichever writer left it changed; on 2026-10-12
        # an autofix edited laws.yml, and the guards in front of each writer were all the
        # protection there was. A person's own `git commit` never passes here.
        def refuse_sacred!(args, confirmed: nil)
          root = File.realpath(@root_path)
          paths = Master::Core::Constitution::Paths
          allowed = Array(confirmed&.paths).map { |path| File.expand_path(path, root) }

          refusal = committed_paths(args).reject { |path| allowed.include?(path) }
                                         .lazy.filter_map { |path| paths.write_refusal(path, root:) }.first
          raise "git commit refused: #{refusal}" if refusal
        end

        # Absolute paths a commit takes: its pathspec file, the paths after --, or else the index.
        def committed_paths(args)
          named = named_paths(args)
          # git answers --show-toplevel with the real path, so names resolve against the real root.
          return named.reject(&:empty?).map { |path| File.expand_path(path, File.realpath(@root_path)) } if named

          staged, = Master::Io::Exec.capture2("git", "-C", @root_path, "diff", "--cached", "--name-only", "-z")
          staged.split("\0").reject(&:empty?).map { |path| File.join(toplevel, path) }
        end

        def named_paths(args)
          listed = args.find { |arg| arg.start_with?("--pathspec-from-file=") }
          return File.read(listed.delete_prefix("--pathspec-from-file=")).split("\0") if listed

          separator = args.index { |arg| arg.match?(/\A-{2}\z/) }
          args.drop(separator + 1) if separator
        end

        def toplevel
          @toplevel ||= Master::Io::Exec.capture2("git", "-C", @root_path, "rev-parse", "--show-toplevel").first.strip
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

      # receipts: a Trace::ToolObserver; the default writes to the canonical event log.
      def initialize(root_path, receipts: nil)
        @root_path = root_path
        @receipts = receipts
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

      # The short SHA of HEAD, or nil outside a repository.
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
