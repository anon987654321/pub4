# frozen_string_literal: true

require "pathname"
require_relative "../../ground/known_good"

module Master
  module Fix
    class FixLoop
      # Commits what an explicitly requested fix-loop pass owns, pushes it, and
      # proves the push landed.
      #
      # The checkout is shared by several sessions and a human. The owned unit
      # is the pass's target files: a change inside them belongs to the request
      # that named them, whenever it was made, and a dirty path outside them is
      # left alone. Without owned paths the pass owns what changed since
      # baseline!, and with no baseline nothing is known to be its own.
      #
      # A commit or push that fails raises after the event is published: a fix
      # loop that asked to deliver and could not must stop, not report success.
      class Committer
        LINT_TIMEOUT_SECONDS = 20
        FINDING_LINES = 40

        def initialize(git:, bus: nil, root: nil, ground_truth: nil, preserve_user_intent: nil)
          @git = git
          @bus = bus
          @root = root
          @ground_truth = ground_truth
          @preserve_user_intent = preserve_user_intent
          @baseline = nil
          # One commit-and-push at a time. Rule groups run in threads, and the
          # index is shared: two commits interleaving `git add` would let one
          # fix ride another's staging, which is the sweep this class exists
          # to refuse.
          @commit_mutex = Mutex.new
          @transaction = nil
          @known_good = root ? Ground::KnownGood.new(root:, bus:) : nil
          @boundary_scope = nil
        end

        def baseline!(scope: nil)
          @baseline = @git.changed_paths
          @boundary_scope = normalize_boundary_scope(scope)
        rescue StandardError => e
          @bus&.publish("fix_loop:commit_error", error: e.message)
          raise "cannot establish fix transaction baseline: #{e.class}: #{e.message}"
        end

        # findings are the violations the pass set out to fix; the ones in a
        # committed file are named in the body, so git log says which rule each
        # runtime commit answered.
        def begin_transaction!(transaction)
          @commit_mutex.synchronize do
            raise "fix transaction already active" if @transaction

            transaction.begin!
            @transaction = transaction
          end
        end

        def abort_transaction!
          @commit_mutex.synchronize do
            transaction = @transaction
            @transaction = nil
            result = transaction&.rollback!
            @boundary_scope = nil
            result
          end
        end

        def finish_transaction(message, findings: [], owned_paths: nil)
          @commit_mutex.synchronize do
            transaction = @transaction
            return Result.err("no active fix transaction", category: :infrastructure) unless transaction

            paths = own_changes(owned_paths)
            return finish_empty_transaction(transaction) if paths.empty?

            prepared, blocked = prepare_for_delivery(transaction, message, paths)
            return blocked if blocked

            deliver_and_commit(transaction:, message:, findings:, prepared:)
          rescue StandardError => e
            @bus&.publish("fix_loop:commit_error", error: e.message)
            @transaction = nil
            transaction&.delivery&.preserve! if transaction&.active?
            Result.err("fix transaction delivery: #{e.message}", category: :infrastructure)
          end
        ensure
          @boundary_scope = nil unless @transaction
        end

        # Runs the two checks that can block delivery -- concurrent changes,
        # then the same validate_paths finish_transaction always ran here --
        # exactly once each, in the same order, with the same rollback on
        # either failure. Returns [prepared, nil] to proceed or [nil, Result]
        # to stop, so the caller never re-runs validate_paths (which lints
        # and re-checks intent, not a free call to repeat).
        def commit_if_dirty(message, findings: [], owned_paths: nil)
          @commit_mutex.synchronize do
            if @transaction
              paths = own_changes(owned_paths)
              @transaction.observe!
              @bus&.publish("fix_loop:transaction_changes", paths:) unless paths.empty?
              return :staged
            end

            commit_if_dirty!(message, findings:, owned_paths:)
          end
        end

        private

        # Runs the two checks that can block delivery -- concurrent changes,
        # then the same validate_paths finish_transaction always ran here --
        # exactly once each, in the same order, with the same rollback on
        # either failure. Returns [prepared, nil] to proceed or [nil, Result]
        # to stop, so the caller never re-runs validate_paths (which lints
        # and re-checks intent, not a free call to repeat).
        def prepare_for_delivery(transaction, message, paths)
          conflicts = transaction.conflicts
          unless conflicts.empty?
            @transaction = nil
            transaction.rollback!
            return [nil, Result.err("fix transaction detected concurrent changes in #{conflicts.join(", ")}", category: :policy)]
          end

          prepared = validate_paths(message, paths)
          return [prepared, nil] if prepared

          @transaction = nil
          transaction.rollback!
          [nil, Result.err("fix transaction blocked before delivery", category: :policy)]
        end

        def deliver_and_commit(transaction:, message:, findings:, prepared:)
          head_before = @git.head
          transaction.delivery.begin!(head_before:)
          @transaction = nil
          begin
            result = commit_paths(message, findings, prepared, transaction:)
            transaction.finalize!
            result
          rescue StandardError => e
            committed = head_changed?(head_before)
            if committed
              @bus&.publish("fix_loop:commit_error", error: e.message, committed: true)
              Result.err("fix transaction delivery pending: #{e.message}", category: :infrastructure)
            else
              rollback = transaction.rollback!
              @bus&.publish("fix_loop:commit_error", error: e.message, committed: false)
              rollback.err? ? rollback : Result.err("fix transaction delivery: #{e.message}", category: :infrastructure)
            end
          end
        end

        def commit_if_dirty!(message, findings: [], owned_paths: nil)
          paths = own_changes(owned_paths)
          return :noop if paths.empty?
          return :blocked unless validate_paths(message, paths)

          @git.commit(with_finding_ids(message, findings, paths), paths:)
          @git.push
          verify_push!(paths)
          promote_known_good(@git.head, paths)
          @bus&.publish("ops:commit", message: message.to_s[0, 120], head: @git.head, paths:, findings:)
          Result.ok(:committed)
        rescue StandardError => e
          @bus&.publish("fix_loop:commit_error", error: e.message)
          raise
        end

        def validate_paths(message, paths)
          return false unless boundary_scope_ok?(paths)

          broken = ruby_files(paths).reject { |path| ruby_parses?(path) }
          return block_commit(broken) && false unless broken.empty?
          return block_commit_intent(message) && false unless intent_preserved?(message, paths)
          return block_commit_ground_truth && false unless ground_truth_fresh?(paths)
          return false unless lint_changed_ruby(paths)

          paths
        end

        def finish_empty_transaction(transaction)
          @transaction = nil
          transaction.finalize!
          Result.ok(:noop)
        end

        def head_changed?(before)
          after = @git.head
          before && after && before != after
        rescue StandardError
          false
        end

        def commit_paths(message, findings, paths, transaction:)
          @git.commit(with_finding_ids(message, findings, paths), paths:)
          head_after = @git.head
          transaction.delivery.record_commit!(head_after:)
          @git.push
          verify_push!(paths)
          promote_known_good(head_after, paths)
          @bus&.publish("ops:commit", message: message.to_s[0, 120], head: head_after, paths:, findings:)
          Result.ok(:committed)
        end

        def promote_known_good(commit, paths)
          return unless @known_good

          result = @known_good.promote!(commit:, paths:)
          @bus&.publish("runtime:promotion_degraded", commit:) if result.err?
          result
        end

        def with_finding_ids(message, findings, paths)
          lines = Array(findings).filter_map do |finding|
            file = finding[:file].to_s.delete_prefix("#{@root}/")
            "#{finding[:rule]} #{file}:#{finding[:line].to_i}" if paths.include?(file)
          end.uniq
          return message.to_s if lines.empty?

          extra = lines.size > FINDING_LINES ? ["and #{lines.size - FINDING_LINES} more"] : []
          [message.to_s, "", *lines.first(FINDING_LINES), *extra].join("\n")
        end

        def own_changes(owned_paths)
          changed = @git.changed_paths
          return @baseline ? changed - @baseline : [] if owned_paths.nil?

          changed & Array(owned_paths).filter_map { |path| relative(path) }.uniq
        end

        # changed_paths are relative to the git -C root, which is @root.
        def relative(path)
          value = path.to_s
          return if value.empty?
          return value unless Pathname.new(value).absolute?

          Pathname.new(value).relative_path_from(Pathname.new(@root)).to_s
        rescue ArgumentError
          nil
        end

        # Only commits still ahead mean the push missed. Behind is the remote
        # moving on, which a push that succeeded has no quarrel with.
        def verify_push!(paths)
          ahead, = @git.ahead_behind
          return if ahead.zero?

          raise "git push left #{ahead} commit#{"s" unless ahead == 1} unpushed: #{paths.join(", ")}"
        end

        def normalize_boundary_scope(scope)
          return nil if scope.nil?

          values = Array(scope).map(&:to_s).reject(&:empty?).uniq
          known = Master::Phoenix.boundaries(root: @root).map(&:name)
          unknown = values - known
          raise ArgumentError, "unknown phoenix boundary scope: #{unknown.join(", ")}" unless unknown.empty?

          values.freeze
        end

        def boundary_scope_ok?(paths)
          return true if @boundary_scope.nil? || @boundary_scope.empty?

          foreign = Array(paths).filter_map do |path|
            boundary = Master::Phoenix.boundary_for(path, root: @root)
            next if boundary && @boundary_scope.include?(boundary)

            [path, boundary || "unowned"]
          end
          return true if foreign.empty?

          boundaries = foreign.map(&:last).uniq
          @bus&.publish(
            "fix_loop:commit_blocked",
            reason: "architecture_scope",
            scope: @boundary_scope,
            paths: foreign.map(&:first),
            boundaries:,
          )
          Master::Trace::Dmesg.status(
            "fix0",
            "architecture scope blocked: #{boundaries.join(", ")} outside #{@boundary_scope.join(", ")}"
          )
          false
        end

        def block_commit(files)
          @bus&.publish("fix_loop:commit_blocked", reason: "syntax", files:)
          nil
        end

        def block_commit_intent(message)
          @bus&.publish("fix_loop:commit_blocked", reason: "preserve_user_intent", message: message.to_s[0, 120])
          nil
        end

        def block_commit_ground_truth
          @bus&.publish("fix_loop:commit_blocked", reason: "ground_truth")
          nil
        end

        def intent_preserved?(message, paths)
          return true unless @preserve_user_intent && @root

          result = @preserve_user_intent.assert_preserved!(git_diff(paths), message:)
          result.ok?
        end

        def ground_truth_fresh?(paths)
          return true unless @ground_truth && @root

          stale = ruby_files(paths).reject { |path| @ground_truth.fresh?(path) }
          return true if stale.empty?

          stale.each { |path| @ground_truth.assert_fresh!(path, reason: "commit_creation") }
          false
        end

        def git_diff(paths)
          out, status = Master::Io::Exec.capture2e("git", "-C", @root, "diff", "HEAD", "--", *paths)
          raise "git diff failed while validating user intent" unless status.success?

          out.to_s
        end

        def lint_changed_ruby(paths)
          files = ruby_files(paths)
          return true if files.empty?
          return skip_lint("missing Gemfile") unless bundle_context?

          cmd = [Master::BUNDLE_BIN, "exec", "rubocop", "--fail-level", "E", "--force-exclusion", *files]
          # Io::Exec's own timeout kills rubocop and answers a failed status, so a
          # lint that did not finish blocks the commit. Timeout.timeout around it
          # waited for rubocop anyway, then counted the timeout as a pass, and
          # the commit went in unlinted.
          _out, _err, status = Master::Io::Exec.capture3(*cmd, chdir: @root, timeout: LINT_TIMEOUT_SECONDS)
          if status.success?
            true
          else
            @bus&.publish("fix_loop:commit_blocked", reason: "rubocop", files:)
            false
          end
        rescue Errno::ENOENT, StandardError => e
          @bus&.publish("fix_loop:commit_blocked", reason: "rubocop_unavailable", error: e.message)
          false
        end

        def skip_lint(error)
          @bus&.publish("fix_loop:commit_lint_skipped", error:)
          true
        end

        def bundle_context?
          @root && File.file?(File.join(@root, "Gemfile"))
        end

        # Absolute paths of the Ruby files among the pass's own changes.
        def ruby_files(paths)
          return [] unless @root

          paths.select { |path| path.end_with?(".rb") }.map { |path| File.join(@root, path) }
        end

        def ruby_parses?(absolute_path)
          return true unless File.file?(absolute_path)

          RubyVM::InstructionSequence.compile(File.read(absolute_path))
          true
        rescue SyntaxError => e
          Master::Ground::Swallow.log(e, context: "Committer.ruby_parses?")
          false
        end
      end
    end
  end
end
