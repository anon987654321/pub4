# frozen_string_literal: true

require "fileutils"
require "open3"
require "securerandom"
require "stringio"
require "tmpdir"
require_relative "../io/github_operations"
require_relative "../trace/dmesg"
require_relative "worktree_child_process"
require_relative "worktree_dirty_edits"
require_relative "../boot/paths"

module Master
  module Fix
    # Isolates a writing /fix run from the operator's dirty checkout.
    #
    # The control-plane process keeps its lock and terminal. An internal MASTER
    # child boots from this worktree, so every absolute Master::ROOT reference
    # naturally resolves inside the isolated checkout without teaching the
    # whole runtime about a second root. The parent publishes the resulting
    # branch only after a final read-only gate, then removes the worktree and
    # temporary branch.
    class WorktreeSession
      TREES = MasterPaths::TREES
      include ChildProcess
      include DirtyEdits

      Result = Data.define(:ok, :summary, :base, :head, :branch, :worktree)

      def self.foreign_paths(root:)
        new(root:, io: StringIO.new).foreign_paths
      end

      def foreign_paths
        send(:status_paths, root: @repo_root)
      end

      attr_reader :repo_root

      def initialize(root:, bus: nil, io: $stdout, github: nil)
        @repo_root = repository_root(root)
        @bus = bus
        @io = io
        @github = github || Master::Io::GitHubOperations.new(root: @repo_root, out: io)
      end

      def run(command:, foreign_paths: [], proof_trees: nil, include_dirty: false)
        validate_checkout!

        id = "pid#{Process.pid}-#{SecureRandom.hex(5)}"
        branch = "master/fix-#{id}"
        parent = Dir.mktmpdir("pub4-master-fix-")
        worktree = File.join(parent, "checkout")
        branch_name = git!("rev-parse", "--abbrev-ref", "HEAD")
        local_head = git!("rev-parse", "HEAD")

        fetch_main!
        upstream = git!("rev-parse", "origin/main")
        unless %w[main master].include?(branch_name)
          return refused("auto-merge requires checked-out main")
        end
        unless ancestor?(local_head, upstream)
          return refused(
            "local main has unpushed or divergent commits; publish them before auto-merge",
          )
        end
        base = upstream

        announce("isolating #{id} from #{foreign_paths.size} foreign change(s)")
        git!("worktree", "add", "-b", branch, worktree, base)
        git!("push", "-u", "origin", "HEAD:refs/heads/#{branch}", chdir: worktree)

        included = announce_dirty(worktree, include_dirty:)

        carried = carry_availability_state(worktree)
        announce("lane state carried: #{carried.join(", ")}") unless carried.empty?

        status, lines = run_child(worktree, command)
        unless status
          failed_head = rev_parse(worktree, "HEAD")
          if failed_head == base && own_dirty(worktree, included).empty?
            cleanup_success(worktree:, branch:)
            announce("worker failed before writing anything, worktree and branch removed")
            return Result.new(false, "worker failed; nothing was written, worktree removed", base, failed_head, branch, worktree)
          end
          return preserve(
            worktree:, branch:, base:, head: failed_head,
            summary: "worker failed; worktree and branch retained for recovery",
            lines:
          )
        end

        if (dirty = own_dirty(worktree, included)).any?
          return preserve(
            worktree:, branch:, base:, head: rev_parse(worktree, "HEAD"),
            summary: "#{dirty.size} uncommitted change(s) remain after worker; not published",
            lines:
          )
        end

        head = rev_parse(worktree, "HEAD")
        if head == base
          cleanup_success(worktree:, branch:)
          announce("worker made no committed changes, worktree removed")
          return Result.new(true, "worktree: clean, no changes to publish", base, head, branch, worktree)
        end

        changed = diff_paths(worktree, base, head)
        overlap = changed & Array(foreign_paths).map(&:to_s)
        unless overlap.empty?
          return preserve(
            worktree:, branch:, base:, head:,
            summary: "#{overlap.size} fix path(s) overlap foreign local work; publication refused",
            lines: ["overlap: #{overlap.first(12).join(", ")}"]
          )
        end

        proof_ok, proof_lines = run_proof(worktree, proof_trees:)
        unless proof_ok
          return preserve(
            worktree:, branch:, base:, head:,
            summary: "final proof failed; worktree and branch retained",
            lines: proof_lines
          )
        end

        if (dirty = own_dirty(worktree, included)).any?
          return preserve(
            worktree:, branch:, base:, head:,
            summary: "#{dirty.size} proof-time change(s) appeared; publication refused",
            lines: dirty
          )
        end

        publish!(worktree:, branch:, head:, base:)
        cleanup_success(worktree:, branch:)
        announce("published #{head[0, 12]} to origin/main, worktree removed")

        Result.new(
          true,
          "worktree: published #{head[0, 12]} to origin/main; local checkout untouched",
          base,
          head,
          branch,
          worktree,
        )
      rescue StandardError => e
        announce("failed, #{e.class}: #{e.message}")
        Result.new(false, "worktree failed: #{e.class}: #{e.message}", base, head, branch, worktree)
      ensure
        cleanup_parent(parent) if defined?(parent) && parent && defined?(worktree) && worktree && !File.exist?(worktree)
      end

      private

      def repository_root(root)
        candidate = File.expand_path(root)
        loop do
          return candidate if File.exist?(File.join(candidate, ".git"))

          parent = File.dirname(candidate)
          break if parent == candidate
          candidate = parent
        end
        raise "git checkout not found above #{root}"
      end

      def validate_checkout!
        raise "not a git checkout: #{@repo_root}" unless File.exist?(File.join(@repo_root, ".git"))
        raise "origin/main is required for auto-merge" unless git_ok?("show-ref", "--verify", "refs/remotes/origin/main")
      end

      def fetch_main!
        git!("fetch", "origin", "main")
      end

      def publish!(worktree:, branch:, head:, base:)
        fetch_main!
        upstream = git!("rev-parse", "origin/main")
        raise "origin/main moved during fix; publication refused" unless upstream == base

        git!("push", "-u", "origin", "HEAD:refs/heads/#{branch}", chdir: worktree)

        if @github.github_remote?
          result = @github.publish_and_merge!(
            branch:,
            base: "main",
            expected_head: head,
            title: "MASTER /fix: #{branch}",
            body: <<~BODY,
              Automated MASTER convergence change.

              Base: #{base}
              Head: #{head}

              The isolated worktree completed its final read-only proof before delivery.
              MASTER will not publish directly to main; GitHub is the merge authority.
            BODY
          )
          raise result.summary unless result.ok
          return
        end

        # Local mirrors and integration fixtures keep a simple fast-forward path.
        git!("push", "origin", "HEAD:refs/heads/main", chdir: worktree)
      end

      def cleanup_success(worktree:, branch:)
        git!("worktree", "remove", "--force", worktree)
        git!("branch", "-D", branch)
        begin
          git!("push", "origin", "--delete", branch)
        rescue StandardError => e
          announce("remote branch cleanup warning, #{e.message}")
        end
        cleanup_parent(File.dirname(worktree))
      end

      def preserve(worktree:, branch:, base:, head:, summary:, lines:)
        announce(summary)
        Array(lines).last(12).each { |line| announce("worker| #{line}") }
        announce("retained worktree: #{worktree}")
        announce("retained branch: #{branch}")
        announce("inspect: git -C #{worktree} status --short && git -C #{worktree} log --oneline #{base.to_s[0, 12]}..HEAD")
        announce("discard: git -C #{@repo_root} worktree remove --force #{worktree} && git -C #{@repo_root} branch -D #{branch} && git -C #{@repo_root} push origin --delete #{branch}")
        Result.new(false, summary, base, head, branch, worktree)
      end

      def refused(summary)
        announce(summary)
        Result.new(false, "worktree refused: #{summary}", nil, nil, nil, nil)
      end

      def ancestor?(ancestor, descendant)
        _, status = Open3.capture2e("git", "-C", @repo_root, "merge-base", "--is-ancestor", ancestor, descendant)
        status.success?
      end

      def git_ok?(*args)
        _, status = Open3.capture2e("git", "-C", @repo_root, *args)
        status.success?
      end

      def git!(*args, chdir: @repo_root)
        git_raw!(*args, chdir:).strip
      end

      # Porcelain status records begin with a significant space (" M path"), which
      # strip would eat and shift every path by one character.
      def git_raw!(*args, chdir: @repo_root)
        output, status = Open3.capture2e("git", "-C", chdir, *args)
        raise "git #{args.first} failed: #{output.strip}" unless status.success?

        output
      end

      def rev_parse(root, ref)
        git!("rev-parse", ref, chdir: root)
      end

      def diff_paths(root, base, head)
        output = git!("diff", "--name-only", "-z", base, head, "--", chdir: root)
        output.split("\0").reject(&:empty?)
      end

      def announce(message)
        Master::Trace::Dmesg.status("worktree0", message)
      rescue StandardError
        @io.puts("worktree0: #{message}")
      end

      def cleanup_parent(parent)
        return unless parent && File.directory?(parent)
        FileUtils.remove_entry(parent)
      rescue StandardError
        nil
      end
    end
  end
end
