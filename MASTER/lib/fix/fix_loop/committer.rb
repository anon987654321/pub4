# frozen_string_literal: true

require_relative "../../operator/ruby_runner"

require "pathname"
require_relative "../../ground/known_good"
require_relative "../../operator/ratchet_sponsor"
require_relative "repo_scope"
require_relative "../autofix_guard"
require_relative "../run_budget"
require_relative "../refusals"

module Master
  module Fix
    class FixLoop
      # The hook's lint over the lines a change adds. Files outside the repository, a test's temp tree, are no
      # commit's and are skipped.
      module HouseLint
        TIMEOUT_SECONDS = 180

        module_function

        # The lint0 findings, or [] when clean. A lint that fails without naming one is still a
        # finding, and its last lines of output are the reason.
        def findings(paths, root:)
          files = paths.map { |path| File.expand_path(path, root) }
          files = files.select { |path| path.start_with?("#{Master::REPO_ROOT}/") }
          return [] if files.empty?

          out, err, status = run(files)
          return [] if status.success?

          named = out.lines.grep(/\Alint0: \S+:\d+/).map(&:strip)
          return named unless named.empty?

          said = "#{out}#{err}".lines.map(&:strip).reject(&:empty?).last(3).join(" | ")
          ["bin/operator lint failed: #{said.empty? ? "no output, exit #{status.exitstatus.inspect}" : said[0, 300]}"]
        end

        def run(files)
          operator = File.join(Master::ROOT, "bin", "operator")
          Master::Io::Exec.capture3(RbConfig.ruby, operator, "lint", "--changed-lines", *files,
                                    chdir: Master::ROOT, timeout: TIMEOUT_SECONDS)
        end
      end

      # Commits and publishes each explicitly requested, validated repair
      # checkpoint by default. MASTER_FIX_PUSH=end defers pushes until final
      # verification; every attempted push is proved to have landed.
      #
      # The checkout is shared by several sessions and a human. The owned unit
      # is the pass's target files, less any already dirty when the pass began:
      # that work is not the pass's to commit, and a dirty path outside the
      # targets is left alone too. Without owned paths the pass owns what changed since
      # baseline!, and with no baseline nothing is known to be its own.
      #
      # A commit or push that fails raises after the event is published: a fix
      # loop that asked to deliver and could not must stop, not report success.
      class Committer
        include RepoScope

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
          @related_owned_paths = []
          @known_good = root ? Ground::KnownGood.new(root:, bus:) : nil
          @boundary_scope = nil
          @lease_guard = nil
        end

        # The run's Mission#hold_lease!, called before every commit and push,
        # so a worker that lost its mission's lease delivers nothing.
        attr_writer :lease_guard

        def baseline!(scope: nil)
          # The observation's own autofix writes are this run's, not another writer's dirty work.
          @baseline = changed_everywhere.reject { |path| AutofixGuard.still_as_written?(File.expand_path(path, @root)) }
          @boundary_scope = normalize_boundary_scope(scope)
        rescue StandardError => e
          @bus&.publish("fix_loop:commit_error", error_class: e.class.name, error_present: true)
          raise "cannot establish fix transaction baseline: #{e.class}: #{e.message}"
        end

        # A file dirty when the pass began holds someone else's uncommitted work;
        # a fix landing on it cannot be committed apart from that work.
        def dirty_at_baseline?(path)
          Array(@baseline).include?(relative(path))
        end

        # findings are the violations the pass set out to fix; the ones in a
        # committed file are named in the body, so git log says which rule each
        # runtime commit answered.
        def begin_transaction!(transaction)
          @commit_mutex.synchronize do
            raise "fix transaction already active" if @transaction

            @related_owned_paths = []
            transaction.begin!
            @transaction = transaction
          end
          RunBudget.hold_pass(self)
        end

        def abort_transaction!
          @commit_mutex.synchronize do
            transaction = @transaction
            @transaction = nil
            result = transaction && roll_back_own(transaction)
            @boundary_scope = nil
            @related_owned_paths = []
            result
          end
        end

        def finish_transaction(message, findings: [], owned_paths: nil)
          @commit_mutex.synchronize do
            transaction = @transaction
            return Result.err("no active fix transaction", category: :infrastructure) unless transaction

            # As at a checkpoint, only what this pass wrote; the observation's autofix is the pipeline's.
            paths = written_here(own_changes(owned_paths) - release_foreign(transaction))
            return finish_empty_transaction(transaction) if paths.empty?

            prepared, blocked = prepare_for_delivery(transaction, message, paths)
            return blocked if blocked
            return finish_empty_transaction(transaction) if prepared.empty?

            deliver_and_commit(transaction:, message:, findings:, prepared:)
          rescue StandardError => e
            @bus&.publish("fix_loop:commit_error", error_class: e.class.name, error_present: true)
            @transaction = nil
            transaction&.delivery&.preserve! if transaction&.active?
            Result.err("fix transaction delivery: #{e.message}", category: :infrastructure)
          end
        ensure
          unless @transaction
            @boundary_scope = nil
            @related_owned_paths = []
          end
        end

        # Runs the two checks that can block delivery -- concurrent changes,
        # then the same validate_paths finish_transaction always ran here --
        # exactly once each, in the same order, with the same rollback on
        # either failure. Returns [prepared, nil] to proceed or [nil, Result]
        # to stop, so the caller never re-runs validate_paths (which lints
        # and re-checks intent, not a free call to repeat).
        # Content this run wrote itself and checked (scan, syntax, tests) is recorded as read.
        # The commit's freshness check wants a recorded read of what is on disk, and only the
        # ReadFile tool made one, so every commit of a /fix repair or a RuboCop autocorrect was
        # blocked as stale. A file changed by someone else after this still fails the check.
        def attest_written!(*paths)
          files = paths.flatten
          observe_own_writes(files)
          return unless @ground_truth

          files.each { |path| @ground_truth.record_read!(path) if File.file?(path) }
        end

        # A write /fix makes during a pass is recorded with the pass transaction, so a crash rolls it
        # back. Unrecorded, it read as another writer's edit and the rollback refused every path.
        def observe_own_writes(paths)
          observe = lambda do
            transaction = @transaction
            tracked = transaction&.active? ? transaction.tracked(paths) : []
            transaction.observe_paths!(tracked) unless tracked.empty?
          end

          @commit_mutex.owned? ? observe.call : @commit_mutex.synchronize(&observe)
        end

        def written_unchanged?(path) = @ground_truth.recorded_unchanged?(File.expand_path(path, @root))

        # A mid-pass commit owns the whole corpus, so another writer's save to any corpus file would
        # ride along as /fix's work. It takes only files this run recorded writing (attest_written!)
        # and that no one changed since; the rest are left as they are and named.
        def written_here(paths)
          return paths unless @ground_truth

          mine, foreign = paths.partition { |path| written_unchanged?(path) }
          unless foreign.empty?
            named = foreign.first(3).join(", ")
            Master::Trace::Dmesg.status("deliver0", "left #{foreign.size} file(s) /fix did not write")
          end
          mine
        end

        # Visual refinement may promote structural snapshots only after the
        # rendered quality check passes. Enlist those exact JSON baselines in the
        # current /fix transaction before writing, and refuse operator-owned
        # edits already dirty when this run started.
        def enlist_related_visual_baselines!(paths)
          @commit_mutex.synchronize do
            return Result.err("visual baseline enlistment requires an active fix transaction", category: :policy) unless @transaction&.active?
            return Result.err("visual baseline enlistment has no transaction baseline", category: :policy) if @baseline.nil?

            relative_paths = Array(paths).map { |path| relative(path) }
            return Result.err("visual baseline path is outside the allowed snapshot directory", category: :policy) if relative_paths.any?(&:nil?) ||
              relative_paths.any? { |path| !path.match?(%r{\AMASTER/checks/data/layout_snapshots/[A-Za-z0-9._-]+\.json\z}) }
            return Result.err("visual baseline is already dirty at run start", category: :policy) if (relative_paths & @baseline).any?
            current_changes = Array(@git.changed_paths)
            newly_dirty = (relative_paths - @related_owned_paths) & current_changes
            return Result.err("visual baseline changed concurrently during this run", category: :policy) if newly_dirty.any?
            stale_owned = (relative_paths & @related_owned_paths).reject { |path| @transaction.observed_current?(path) }
            return Result.err("visual baseline changed concurrently during this run", category: :policy) if stale_owned.any?
            return Result.err("visual baseline file is missing", category: :inconclusive) unless relative_paths.all? { |path| File.file?(File.join(@root, path)) }

            boundaries = relative_paths.map { |path| Master::Phoenix.boundary_for(path, root: @root) }
            return Result.err("visual baseline has no declared architecture boundary", category: :policy) if boundaries.any?(&:nil?)

            expanded_scope = @boundary_scope.nil? ? nil : normalize_boundary_scope(@boundary_scope + boundaries)
            enlisted = @transaction.enlist!(relative_paths)
            return enlisted unless enlisted.ok?

            @related_owned_paths = (@related_owned_paths + relative_paths).uniq
            @boundary_scope = expanded_scope
            Result.ok(paths: relative_paths)
          end
        rescue StandardError => e
          Result.err("visual baseline enlistment failed: #{e.class}: #{e.message}", category: :infrastructure)
        end

        # Refresh concurrency evidence only for the related baseline paths that
        # the visual check just wrote itself; do not bless concurrent app edits.
        def observe_related_visual_baseline_writes!(paths)
          @commit_mutex.synchronize do
            return Result.err("visual baseline observation requires an active fix transaction", category: :policy) unless @transaction&.active?

            relative_paths = Array(paths).map { |path| relative(path) }
            return Result.err("visual baseline observation includes an unenlisted path", category: :policy) if relative_paths.any?(&:nil?) ||
              (relative_paths - @related_owned_paths).any?

            @transaction.observe_paths!(relative_paths)
          end
        rescue StandardError => e
          Result.err("visual baseline observation failed: #{e.class}: #{e.message}", category: :infrastructure)
        end

        # Why the last commit was refused: a stream worker's deliver0 line did not reach the log, and
        # the repair that asked could only say "blocked".
        attr_reader :last_refusal

        def commit_if_dirty(message, findings: [], owned_paths: nil)
          @last_refusal = nil
          @commit_mutex.synchronize do
            drop_ended_transaction!
            if @transaction
              return stage_only(owned_paths:, findings:) if stage_commit_mode?

              return checkpoint_transaction(message, findings:, owned_paths:)
            end

            commit_if_dirty!(message, findings:, owned_paths:)
          end
        end

# A validated checkpoint is committed and pushed before repair continues.
# This keeps long sweeps recoverable and the remote close to the actual work.
# MASTER_FIX_PUSH=end explicitly defers publication until final verification.
# Names what would be published first, as the pre-push guard does.
def publish_pending!
  @commit_mutex.synchronize do
    ahead, = @git.ahead_behind
    return :nothing_to_publish if ahead.zero?
    return held(ahead) if no_publish?

    @git.log_between("@{u}").each { |line| Master::Trace::Dmesg.status("deliver0", "publishing #{line}") }
    @git.push
    verify_push!(["#{ahead} commit(s)"])
    @bus&.publish("fix_loop:published", commits: ahead)
    :published
  end
end

private

def push_each?
  ENV.fetch("MASTER_FIX_PUSH", "each") != "end" && !no_publish?
end

# fix-here --no-publish: the run commits locally and leaves the push to its operator.
def no_publish?
  ENV["MASTER_FIX_NO_PUBLISH"] == "1"
end

def held(ahead)
  Master::Trace::Dmesg.status("deliver0", "held, #{ahead} commit(s) left local (MASTER_FIX_NO_PUBLISH=1)")
  :held
end

def push_commit!(paths)
  @lease_guard&.call
  return unless push_each?

  @git.push
  verify_push!(paths)
end

def stage_commit_mode?

          ENV["MASTER_FIX_COMMIT_STAGE"] == "1"
        end

        def stage_only(owned_paths:, findings:)
          paths = own_changes(owned_paths)
          @transaction.observe!
          @bus&.publish("fix_loop:transaction_changes", paths:) unless paths.empty?
          :staged
        end

        # A validated fix is a delivery checkpoint. The transaction remains
        # open so the pass is recoverable, but the pushed commit becomes the
        # rollback floor for its own paths.
        def checkpoint_transaction(message, findings:, owned_paths:)
          transaction = @transaction
          paths = written_here(own_changes(owned_paths))
          return :noop if paths.empty?

          prepared = validate_paths(message, paths)
          return :blocked unless prepared
          return :noop if prepared.empty?

          head_before = @git.head
          transaction.delivery.begin!(head_before:)
          begin
            result = commit_paths(message, findings, prepared, transaction:)
            checkpoint = transaction.checkpoint!(paths)
            raise checkpoint.message if checkpoint.err?

            Master::Trace::Dmesg.status(
              "deliver0", "commit=#{@git.head} push=#{push_each? ? "ok" : "deferred"} paths=#{paths.size}"
            )
            result
          rescue StandardError => e
            committed = head_changed?(head_before)
            if committed
              @transaction = nil
              transaction.delivery.preserve! if transaction.active?
            else
              rollback = roll_back_own(transaction)
              raise "#{e.message}; #{rollback.message}" if rollback.err?
            end
            raise
          end
        end

        # A refused rollback ends the transaction but left it here, so every later fix
        # in the pass failed "transaction not active" and none was committed. The fix
        # is already on disk; it commits on its own, path-scoped, as outside a pass.
        def drop_ended_transaction!
          return unless @transaction && !@transaction.active?

          Master::Trace::Dmesg.status("fix0", "transaction ended mid-pass; later fixes commit on their own")
          @transaction = nil
        end

        # Runs validate_paths, the check that can block delivery, exactly once,
        # with a rollback on failure. Another writer's changes were released
        # before it (release_foreign). Returns [prepared, nil] to proceed or [nil, Result]
        # to stop, so the caller never re-runs validate_paths (which lints
        # and re-checks intent, not a free call to repeat).
        def prepare_for_delivery(transaction, message, paths)
          prepared = validate_paths(message, paths)
          return [prepared, nil] if prepared

          @transaction = nil
          roll_back_own(transaction)
          [nil, Result.err("fix transaction blocked before delivery", category: :policy)]
        end

        # Another writer's edit to a tracked file is left as it stands and the rest of the pass rolls
        # back; refusing the whole rollback for one foreign file left every /fix write in the tree.
        def roll_back_own(transaction)
          left = transaction.release_conflicts!
          result = transaction.rollback!
          report_rollback(result, left)
          result
        end

        # The bus carries the event; dmesg says which files a rollback did not put back.
        def report_rollback(result, left)
          unless left.empty?
            Master::Trace::Dmesg.status("fix0", "rollback left #{left.size} file(s) another writer changed")
          end
          return if result.ok?

          Master::Trace::Dmesg.status("fix0", "rollback refused, the pass's writes stay: #{result.message}"[0, 300])
        end

        # A file that changed under the pass without its write belongs to another writer in the
        # shared checkout. It is left as that writer left it and kept out of this commit; failing
        # the whole pass for it threw away every verified fix the pass held.
        def release_foreign(transaction)
          foreign = transaction.release!(transaction.conflicts)
          return foreign if foreign.empty?

          Master::Trace::Dmesg.status("deliver0", "left #{foreign.size} file(s) another writer changed")
          foreign
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
              rollback = roll_back_own(transaction)
              @bus&.publish("fix_loop:commit_error", error: e.message, committed: false)
              rollback.err? ? rollback : Result.err("fix transaction delivery: #{e.message}", category: :infrastructure)
            end
          end
        end

        def commit_if_dirty!(message, findings: [], owned_paths: nil)
          paths = written_here(own_changes(owned_paths))
          return :noop if paths.empty?

          delivered = validate_paths(message, paths)
          return :blocked unless delivered
          return :noop if delivered.none?

          paths = delivered
          commit_scoped(with_finding_ids(message, findings, paths), paths:)
          push_commit!(paths)

          promote_known_good(@git.head, paths)
          Master::Trace::Dmesg.status(
            "deliver0", "commit=#{@git.head} push=#{push_each? ? "ok" : "deferred"} paths=#{paths.size}"
          )
          @bus&.publish("ops:commit", operation: "commit", head: @git.head, path_count: paths.size, finding_count: Array(findings).size)
          Result.ok(:committed)
        rescue StandardError => e
          @bus&.publish("fix_loop:commit_error", error_class: e.class.name, error_present: true)
          raise
        end

        def validate_paths(message, paths)
          @refusing_paths = paths
          return false unless boundary_scope_ok?(paths)
          return false unless ratchet_sponsorship_ok?(paths)

          broken = ruby_files(paths).reject { |path| ruby_parses?(path) }
          return block_commit(broken) && false unless broken.empty?
          return block_commit_intent(message) && false unless intent_preserved?(message, paths)
          return block_commit_ground_truth(@stale_reads) && false unless ground_truth_fresh?(paths)
          return false unless lint_changed_ruby(paths)

          house_lint_clean(paths)
        end

        # The pre-commit hook runs `bin/operator lint --staged --changed-lines` and refuses a finding in any line a
        # commit adds; rubocop --fail-level E passes a 141-character line it refuses, so the same lint runs here first.
        # Answers the paths to deliver, or false.
        def house_lint_clean(paths)
          found = HouseLint.findings(paths, root: @root)
          return paths if found.empty?

          kept = paths - put_back_refused_autofix(paths, found)
          return kept if kept.size < paths.size && HouseLint.findings(kept, root: @root).empty?

          refuse_commit(reason: "house_lint", findings: found.first(3))
          false
        end

        # An autofix rewrite is not worth a pass. When every finding names a file the autofix wrote and
        # nothing has changed since, those files go back to what they held and the rest delivers: the
        # trailing comma rubocop added to a 141-character line ended every MASTER pass at its first delivery.
        def put_back_refused_autofix(paths, found)
          absolute = paths.to_h { |path| [File.expand_path(path, @root), path] }
          named = lint_blamed(absolute.keys, found)
          return [] unless named&.all? { |path| AutofixGuard.still_as_written?(path) }

          reverted, = AutofixGuard.revert_written!(named)
          Master::Trace::Dmesg.status("deliver0", "put back #{reverted.size} autofix file(s) the house lint refused")
          absolute.values_at(*reverted)
        end

        # The delivered files each finding names, or nil when one names no file among them. The lint names
        # a path from the repository root; the delivery holds it from the tree's.
        def lint_blamed(files, found)
          named = found.map do |line|
            rel = line[/\Alint0: (\S+?):\d+/, 1]
            rel && files.find { |path| path.end_with?("/#{rel}") }
          end
          named.include?(nil) ? nil : named.uniq
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
          marker = Master::Fix::Transaction::Delivery.marker(transaction.id)
          commit_scoped("#{with_finding_ids(message, findings, paths)}\n\n#{marker}", paths:)
          head_after = @git.head
          transaction.delivery.record_commit!(head_after:)
          push_commit!(paths)
          promote_known_good(head_after, paths)
          @bus&.publish("ops:commit", operation: "commit", head: head_after, path_count: paths.size, finding_count: Array(findings).size)
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
            "#{finding[:law]} #{file}:#{finding[:line].to_i}" if paths.include?(file)
          end.uniq
          return message.to_s if lines.empty?

          extra = lines.size > FINDING_LINES ? ["and #{lines.size - FINDING_LINES} more"] : []
          [message.to_s, "", *lines.first(FINDING_LINES), *extra].join("\n")
        end

        def own_changes(owned_paths)
          changed = changed_everywhere
          return @baseline ? changed - @baseline : [] if owned_paths.nil?

          requested = Array(owned_paths).filter_map { |path| relative(path) }
          requested.concat(@related_owned_paths)
          owned = changed & requested.uniq
          held_back = owned & Array(@baseline)
          @bus&.publish("fix_loop:baseline_dirty_excluded", paths: held_back) unless held_back.empty?
          owned - held_back
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
          return if scope.nil?

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

          refuse_commit(reason: "architecture_scope", boundaries: foreign.map(&:last).uniq, scope: @boundary_scope,
                        paths: foreign.map(&:first))
          false
        end

        # The lint the pre-commit hook runs, and rubocop beside it, are the lint gate; every other
        # refusal here is the commit gate.
        LINT_REFUSALS = %w[house_lint rubocop rubocop_unavailable].freeze

        # The bus event for subscribers, and one refusal row (Fix::Refusals) so the log says why a
        # fix that passed every check was still not committed.
        def refuse_commit(**payload)
          published = @bus&.publish("fix_loop:commit_blocked", **payload)
          detail = payload.except(:reason).map { |key, value| "#{key} #{Array(value).map { |item| item.to_s.delete_prefix("#{@root}/") }.join(",")[0, 120]}" }
          @last_refusal = ([payload[:reason]] + detail).join(", ")

          record_refusal(payload)
          published
        end

        def record_refusal(payload)
          gate = LINT_REFUSALS.include?(payload[:reason].to_s) ? :lint : :commit
          files = Array(payload[:files] || payload[:paths] || @refusing_paths)
          files = ["(no paths)"] if files.empty?
          Refusals.record(gate:, file: files, reason: @last_refusal, root: @root || MasterPaths::REPO)
        end

        def ratchet_sponsorship_ok?(paths)
          ::Operator::RatchetSponsor.validate!(root: @root, changed_paths: paths)
          true
        rescue StandardError => e
          refuse_commit(reason: "ratchet_sponsorship", error: e.message)
          false
        end

        def block_commit(files)
          refuse_commit(reason: "syntax", files:)
          nil
        end

        def block_commit_intent(message)
          refuse_commit(reason: "preserve_user_intent", message: message.to_s[0, 120])
          nil
        end

        def block_commit_ground_truth(stale)
          refuse_commit(reason: "ground_truth", files: stale)
          nil
        end

        def intent_preserved?(message, paths)
          return true unless @preserve_user_intent && @root

          result = @preserve_user_intent.assert_preserved!(git_diff(paths), message:)
          result.ok?
        end

        def ground_truth_fresh?(paths)
          return true unless @ground_truth && @root

          # A write this run recorded and no one changed since is fresh however long the repair took;
          # the age window is for what was read, and expired a slow repair's own commit.
          truth = @ground_truth
          stale = ruby_files(paths).reject { |path| truth.fresh?(path) || truth.recorded_unchanged?(path) }
          @stale_reads = stale
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

          cmd = [::Operator::RubyRunner.bundle_cmd(root: @root), "exec", "rubocop", "--fail-level", "E", "--force-exclusion", *files]
          # Io::Exec's own timeout kills rubocop and answers a failed status, so a
          # lint that did not finish blocks the commit. Timeout.timeout around it
          # waited for rubocop anyway, then counted the timeout as a pass, and
          # the commit went in unlinted.
          _out, _err, status = Master::Io::Exec.capture3(*cmd, chdir: @root, timeout: LINT_TIMEOUT_SECONDS)
          if status.success?
            true
          else
            refuse_commit(reason: "rubocop", files:)
            false
          end
        rescue Errno::ENOENT, StandardError => e
          refuse_commit(reason: "rubocop_unavailable", error: e.message)
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
