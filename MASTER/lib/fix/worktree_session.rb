# frozen_string_literal: true

require "fileutils"
require_relative "../io/exec"
require "securerandom"
require "shellwords"
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

      Result = Data.define(:ok, :summary, :base, :head, :branch, :worktree, :category)
      MIN_FREE_DISK_GB = 2.0

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
        phase = :preflight
        published_head = nil
        validate_checkout!
        configured_timeout_s("MASTER_FIX_WORKTREE_TIMEOUT_S")
        configured_timeout_s("MASTER_FIX_PROOF_TIMEOUT_S")
        free_gb = disk_free_gb
        return refused("cannot measure free disk space; worktree was not created") unless free_gb
        return refused(format("disk preflight: %.2f GB free, %.2f GB required; worktree was not created",
                              free_gb, MIN_FREE_DISK_GB)) if free_gb < MIN_FREE_DISK_GB

        phase = :setup
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
        if carry_gate_baseline(worktree)
          announce("gate baseline cache carried; the current tree fingerprint decides reuse")
        end

        phase = :worker
        status, lines = run_child(worktree, command)
        terminal_failure = worker_terminal_failure(lines)
        timeout_line = lines.find { |line| line.match?(/child timeout after \d+s/i) }
        cancelled_line = lines.find { |line| line.match?(/child cancelled by operator/i) }
        failure_reason = if timeout_line
                           timeout_line.sub(/\Aworktree0:\s*/i, "")
                         elsif cancelled_line
                           "worker cancelled by operator"
                         elsif terminal_failure
                           "worker reported an incomplete terminal state: #{terminal_failure.strip}"
                         elsif !status
                           "worker exited unsuccessfully"
                         elsif !worker_completion_seen?(lines)
                           "worker exited without an explicit completion report"
                         end

        if failure_reason
          failed_head = rev_parse(worktree, "HEAD")
          failure_category = if timeout_line
            :timeout
          elsif cancelled_line
            :abort
          elsif terminal_failure
            worker_terminal_category(terminal_failure)
          elsif !status
            :crash
          else
            :validation
          end
          if failed_head == base && own_dirty(worktree, included).empty?
            remote_cleanup = cleanup_success(worktree:, branch:)
            note = cleanup_note(remote_cleanup, branch)
            announce("#{failure_reason}; no changes were written, worktree removed#{note}")
            return Result.new(false, "#{failure_reason}; no changes were written, worktree removed#{note}", base, failed_head, branch, worktree, failure_category)
          end
          return preserve(
            worktree:, branch:, base:, head: failed_head,
            summary: "#{failure_reason}; partial work retained and not published",
            lines:, category: failure_category
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
          remote_cleanup = cleanup_success(worktree:, branch:)
          note = cleanup_note(remote_cleanup, branch)
          announce("worker made no committed changes, worktree removed#{note}")
          return Result.new(true, "worktree: clean, no changes to publish#{note}", base, head, branch, worktree, nil)
        end

        changed = diff_paths(worktree, base, head)
        overlap = changed & Array(foreign_paths).map(&:to_s)
        unless overlap.empty?
          return preserve(
            worktree:, branch:, base:, head:,
            summary: "#{overlap.size} fix path(s) overlap foreign local work; publication refused",
            lines: ["overlap: #{overlap.first(12).join(", ")}"],
            category: :policy
          )
        end

        proof_ok, proof_lines = run_proof(worktree, proof_trees:)
        unless proof_ok
          timeout = proof_lines.find { |line| line.match?(/child timeout after \d+s/i) }
          cancelled = proof_lines.any? { |line| line.match?(/child cancelled by operator/i) }
          reason = if timeout
                     "final proof timed out; worktree and branch retained"
                   elsif cancelled
                     "final proof cancelled by operator; worktree and branch retained"
                   else
                     "final proof failed; worktree and branch retained"
                   end
          proof_category = if timeout
            :timeout
          elsif cancelled
            :abort
          else
            :validation
          end
          return preserve(worktree:, branch:, base:, head:, summary: reason, lines: proof_lines, category: proof_category)
        end

        if (dirty = own_dirty(worktree, included)).any?
          return preserve(
            worktree:, branch:, base:, head:,
            summary: "#{dirty.size} proof-time change(s) appeared; publication refused",
            lines: dirty
          )
        end

        phase = :publish
        published_head = publish!(worktree:, branch:, head:, base:)
        phase = :cleanup
        remote_cleanup = cleanup_success(worktree:, branch:)
        note = cleanup_note(remote_cleanup, branch)
        announce("published #{published_head.to_s[0, 12]} to origin/main (candidate #{head[0, 12]}), worktree removed#{note}")

        Result.new(
          true,
          "worktree: published candidate #{head[0, 12]} as #{published_head.to_s[0, 12]} to origin/main; local checkout untouched#{note}",
          base,
          head,
          branch,
          worktree,
          nil,
        )
      rescue StandardError, Interrupt => e
        category = if published_head
          :infrastructure
        elsif phase == :publish
          :delivery_failed
        elsif e.is_a?(Interrupt)
          :abort
        elsif phase == :preflight
          :validation
        else
          :infrastructure
        end
        detail = if published_head
          "delivery completed as #{published_head.to_s[0, 12]}, but worktree cleanup failed (#{e.class})"
        elsif phase == :publish
          "DELIVERY_FAILED: final publication did not complete cleanly (#{e.class})"
        elsif e.is_a?(Interrupt)
          "worktree cancelled by operator"
        else
          "worktree failed, #{e.class}: #{safe_error_message(e)}"
        end
        announce(detail)
        if defined?(worktree) && worktree && File.directory?(worktree)
          recovered_head = begin
            git!("rev-parse", "HEAD", chdir: worktree)
          rescue StandardError, Interrupt
            head
          end
          announce("retained worktree: #{worktree}")
          announce("retained branch: #{branch}") if defined?(branch) && branch
          announce("inspect: #{inspect_command(worktree, base)}")
          announce("discard: #{discard_command(worktree, branch)}") if defined?(branch) && branch
          recovery = "#{detail}; retained worktree: #{worktree}; branch: #{branch}"
          Result.new(false, recovery, base, recovered_head, branch, worktree, category)
        else
          Result.new(false, detail, base, head, branch, worktree, category)
        end
      ensure
        cleanup_parent(parent) if defined?(parent) && parent && defined?(worktree) && worktree && !File.exist?(worktree)
      end

      private

      # Check both filesystems before creating an isolated checkout: on macOS
      # the repository and Dir.tmpdir may be mounted through different APFS paths.
      # df -kP's fourth column is available KiB, consistent with ResourceBudget.
      def disk_free_gb
        [@repo_root, Dir.tmpdir].map do |path|
          output, status = Master::Io::Exec.capture2e("df", "-kP", path)
          return nil unless status.success?

          fields = output.lines.last.to_s.split
          available_kb = Integer(fields.fetch(3), 10)
          available_kb / (1024.0 * 1024.0)
        rescue ArgumentError, IndexError, SystemCallError
          return nil
        end.min
      end

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
          merged_sha = result.merged_sha.to_s
          raise "GitHub reported MERGED without a valid merge commit SHA" unless merged_sha.match?(/\A[0-9a-f]{40}\z/i)

          return merged_sha
        end

        # Local mirrors and integration fixtures keep a simple fast-forward path.
        git!("push", "origin", "HEAD:refs/heads/main", chdir: worktree)
        head
      end

      def cleanup_success(worktree:, branch:)
        git!("worktree", "remove", "--force", worktree)
        git!("branch", "-D", branch)
        remote_cleanup = :removed
        begin
          git!("push", "origin", "--delete", branch)
        rescue StandardError => e
          remote_cleanup = remote_branch_state(branch)
          if remote_cleanup == :absent
            remote_cleanup = :already_absent
            announce("remote branch already absent, cleanup complete: origin/#{branch}")
          elsif remote_cleanup == :present
            remote_cleanup = :retained
            announce("remote branch cleanup warning, retained origin/#{branch}: #{safe_error_message(e)}")
          else
            remote_cleanup = :unknown
            announce("remote branch cleanup state unknown for origin/#{branch}: #{e.message}")
          end
        end
        cleanup_parent(File.dirname(worktree))
        remote_cleanup
      end

      # GitHub may delete a merged PR branch before local cleanup runs. Distinguish
      # that from a failed deletion, and do not guess when the remote cannot be read.
      def remote_branch_state(branch)
        output, status = Master::Io::Exec.capture2e(
          "git", "-C", @repo_root, "ls-remote", "--heads", "origin", "refs/heads/#{branch}"
        )
        return :unknown unless status.success?

        output.to_s.empty? ? :absent : :present
      rescue StandardError
        :unknown
      end

      def cleanup_note(remote_cleanup, branch)
        case remote_cleanup
        when :removed, :already_absent
          ""
        when :retained
          "; remote branch cleanup failed, retained origin/#{branch}"
        else
          "; remote branch cleanup state unknown for origin/#{branch}"
        end
      end

      def preserve(worktree:, branch:, base:, head:, summary:, lines:, category: :validation)
        announce(summary)
        Array(lines).last(12).each { |line| announce("worker| #{line}") }
        announce("retained worktree: #{worktree}")
        announce("retained branch: #{branch}")
        announce("inspect: #{inspect_command(worktree, base)}")
        announce("discard: #{discard_command(worktree, branch)}")
        Result.new(false, summary, base, head, branch, worktree, category)
      end

      def inspect_command(worktree, base = nil)
        status = Shellwords.join(["git", "-C", worktree, "status", "--short"])
        log = ["git", "-C", worktree, "log", "--oneline"]
        log << "#{base.to_s[0, 12]}..HEAD" unless base.to_s.empty?
        "#{status} && #{Shellwords.join(log)}"
      end

      def discard_command(worktree, branch)
        [
          ["git", "-C", @repo_root, "worktree", "remove", "--force", worktree],
          ["git", "-C", @repo_root, "branch", "-D", branch],
          ["git", "-C", @repo_root, "push", "origin", "--delete", branch],
        ].map { |args| Shellwords.join(args) }.join(" && ")
      end

      def refused(summary)
        announce(summary)
        Result.new(false, "worktree refused: #{summary}", nil, nil, nil, nil, :policy)
      end

      # Exit status zero is not sufficient: the CLI can print an explicit
      # incomplete terminal result. Never report that run as a clean success.
      def worker_terminal_failure(lines)
        Array(lines).find do |line|
          line.match?(/\A(?:review|fix)\d+(?:\s+at\s+[^:]+)?\s*:\s*(?:incomplete|failed|crash|skip|blocked|validation_failed|delivery_failed|timeout|human_decision|plateau|reloading|complete\s+with\s+open\s+findings)\b/i)
        end
      end

      # The worker's terminal vocabulary maps to the shared Result retry policy.
      # A failed delivery can be retried; an operator veto must not be treated as validation.
      def worker_terminal_category(line)
        state = line.to_s.match(/:\s*(incomplete|failed|crash|skip|blocked|validation_failed|delivery_failed|timeout|human_decision|plateau|reloading|complete\s+with\s+open\s+findings)\b/i)&.captures&.first&.downcase
        case state
        when "delivery_failed" then :delivery_failed
        when "timeout" then :timeout
        when "crash" then :crash
        when "skip" then :skip
        when "blocked" then :policy
        when "human_decision" then :human_decision
        when "plateau", "complete with open findings" then :plateau
        when "reloading" then :reloading
        when "failed" then :failed
        else :validation
        end
      end

      # A zero exit is not proof that the requested command ran to completion.
      # The CLI's final review report is the explicit completion contract.
      def worker_completion_seen?(lines)
        Array(lines).any? do |line|
          line.match?(/\A(?:review|fix)\d+(?:\s+at\s+[^:]+)?\s*:\s*complete\b/i)
        end
      end

      def ancestor?(ancestor, descendant)
        _, status = Master::Io::Exec.capture2e("git", "-C", @repo_root, "merge-base", "--is-ancestor", ancestor, descendant)
        status.success?
      end

      def git_ok?(*args)
        _, status = Master::Io::Exec.capture2e("git", "-C", @repo_root, *args)
        status.success?
      end

      # External command failures can echo authenticated URLs, bearer credentials or
      # provider tokens. Keep useful diagnostics while removing credential-shaped data
      # before an exception reaches the operator log or a Result summary.
      def safe_error_message(error)
        message = error.message.to_s
        message = message.gsub(%r{(https?://)[^\s/@]+(?::[^\s/@]*)?@}i, '\1[redacted]@')
        message = message.gsub(/\b(?:github_pat_[A-Za-z0-9_]{20,}|gh[pousr]_[A-Za-z0-9]{20,}|glpat-[A-Za-z0-9_-]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}|sk-[A-Za-z0-9_-]{20,})\b/i, '[redacted-token]')
        message = message.gsub(/\b(Bearer\s+)[A-Za-z0-9._~+\/=-]+/i, '\1[redacted]')
        message = message.gsub(/(\b(?:access[_-]?token|refresh[_-]?token|token|api[_-]?key|password|secret)\b\s*[:=]\s*)["']?[^"' \t\r\n,;]+["']?/i, '\1[redacted]')
        message = message.gsub(/([?&](?:token|key|password|secret|signature|sig)=)[^&#\s]+/i, '\1[redacted]')
        message = message.lines.map(&:chomp).join(' ').gsub(/\s+/, ' ').strip
        message.slice(0, 500)
      end

      def git!(*args, chdir: @repo_root)
        git_raw!(*args, chdir:).strip
      end

      # Porcelain status records begin with a significant space (" M path"), which
      # strip would eat and shift every path by one character.
      def git_raw!(*args, chdir: @repo_root)
        output, status = Master::Io::Exec.capture2e("git", "-C", chdir, *args)
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
