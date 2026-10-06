# frozen_string_literal: true

require "fileutils"
require "open3"
require "securerandom"
require "stringio"
require "tmpdir"

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
      TREES = %w[MASTER RAILS OPENBSD STUDIO].freeze
      Result = Data.define(:ok, :summary, :base, :head, :branch, :worktree)

      def self.foreign_paths(root:)
        session = new(root:, io: StringIO.new)
        session.status_paths(root: session.repo_root)
      end

      attr_reader :repo_root

      def initialize(root:, bus: nil, io: $stdout)
        @repo_root = repository_root(root)
        @bus = bus
        @io = io
      end

      def run(command:, foreign_paths: [], proof_trees: nil)
        validate_checkout!

        id = "pid#{Process.pid}-#{SecureRandom.hex(5)}"
        branch = "master/fix-#{id}"
        parent = Dir.mktmpdir("pub4-master-fix-")
        worktree = File.join(parent, "checkout")
        base = git!("rev-parse", "HEAD")

        fetch_main!
        upstream = git!("rev-parse", "origin/main")
        unless ancestor?(upstream, base)
          return refused(
            "local HEAD is behind origin/main; update the main checkout before /fix"
          )
        end

        announce("isolating #{id} from #{foreign_paths.size} foreign change(s)")
        git!("worktree", "add", "-b", branch, worktree, base)
        git!("push", "-u", "origin", "HEAD:refs/heads/#{branch}", chdir: worktree)

        status, lines = run_child(worktree, command)
        unless status
          return preserve(
            worktree:, branch:, base:, head: rev_parse(worktree, "HEAD"),
            summary: "worker failed; worktree and branch retained for recovery",
            lines:
          )
        end

        if (dirty = status_paths(root: worktree)).any?
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

        if (dirty = status_paths(root: worktree)).any?
          return preserve(
            worktree:, branch:, base:, head:,
            summary: "#{dirty.size} proof-time change(s) appeared; publication refused",
            lines: dirty
          )
        end

        publish!(worktree:, branch:, head:)
        cleanup_success(worktree:, branch:)
        announce("published #{head[0, 12]} to origin/main, worktree removed")

        Result.new(
          true,
          "worktree: published #{head[0, 12]} to origin/main; local checkout untouched",
          base,
          head,
          branch,
          worktree
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

      def run_child(worktree, command)
        env = ENV.to_h.merge(
          "MASTER_INTERNAL_CHILD" => "1",
          "MASTER_FIX_WORKTREE_CHILD" => "1",
          "MASTER_PROCESS_LOCK_FD" => nil,
          "MASTER_CONTROL_PLANE" => nil
        )
        run_stream(env, File.join(worktree, "MASTER", "bin", "master"), command, chdir: worktree)
      end

      def run_proof(worktree, proof_trees:)
        command = File.join(worktree, "MASTER", "bin", "operator")
        args = ["gate", "--scan-only"]
        trees = Array(proof_trees).map(&:to_s).select { |tree| TREES.include?(tree) }.uniq
        args << "--tree=#{trees.join(",")}" unless trees.empty? || trees.sort == TREES.sort
        run_stream(ENV.to_h.merge("MASTER_INTERNAL_CHILD" => "1"), command, *args, chdir: worktree)
      end

      def run_stream(env, command, *args, chdir:)
        lines = []
        status = nil
        Open3.popen2e(env, command, *args, chdir:) do |stdin, io, wait_thr|
          stdin.close
          io.each_line do |line|
            @io.write(line)
            @io.flush
            lines << line.rstrip
          end
          status = wait_thr.value
        end
        [status.success?, lines]
      end

      def publish!(worktree:, branch:, head:)
        fetch_main!
        upstream = git!("rev-parse", "origin/main")
        raise "origin/main moved during fix; publication refused" unless ancestor?(upstream, head)

        git!("push", "origin", "refs/heads/#{branch}:refs/heads/main", chdir: worktree)
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
        output, status = Open3.capture2e("git", "-C", chdir, *args)
        raise "git #{args.first} failed: #{output.strip}" unless status.success?

        output.strip
      end

      def rev_parse(root, ref)
        git!("rev-parse", ref, chdir: root)
      end

      def status_paths(root:)
        output = git!("status", "--porcelain=v1", "-z", "--untracked-files=all", chdir: root)
        parse_nul_paths(output)
      end

      def diff_paths(root, base, head)
        output = git!("diff", "--name-only", "-z", base, head, "--", chdir: root)
        output.split("\0").reject(&:empty?)
      end

      def parse_nul_paths(output)
        records = output.to_s.split("\0")
        paths = []
        index = 0
        while index < records.length
          record = records[index]
          break if record.empty?

          status = record[0, 2].to_s
          path = record[3..].to_s
          paths << path unless path.empty?
          if status.match?(/[RC]/)
            index += 1
            renamed = records[index].to_s
            paths << renamed unless renamed.empty?
          end
          index += 1
        end
        paths
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
