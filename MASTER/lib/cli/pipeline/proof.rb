# frozen_string_literal: true

require "set"
require_relative "../../operator/gate_chain"
require_relative "proof/reading"

module Master
  module CLI
    class Pipeline
      # The proof a writing pass owes, measured against the same proof run on
      # the untouched tree before the repair.
      #
      # Main is rarely green on a shared repository: other sessions' work in
      # flight, and ceilings an approved design change went over, keep some
      # gate or test red whatever /fix does. A proof that demanded green
      # delivered nothing from a pass that left the tree no worse. So the proof
      # holds when every failure after the repair was failing before it, no
      # ratchet row counts higher, and no suite that finished before stopped
      # finishing. A baseline that could not be read falls back to green.
      #
      # The commands are the ladder's own, so there is one spelling of what
      # proves each tree and this stage cannot drift from it.
      module Proof
        PROOF_TAIL = 12

        # A proof runs whole suites, and a suite holds tests that run /fix,
        # whose own proof would start the suites again; the child of a proof
        # skips it.
        PROOF_ENV = "MASTER_IN_PROOF"

        # runner.rb exits 3 when no gate failed and some measured nothing — off
        # the deploy host that is deploy_drift's stamps, and the rendered half
        # when Chrome or the apps are absent. GateResult's standing decision is
        # that "could not measure" blocks only under GATE_STRICT_INCONCLUSIVE,
        # which the runner itself turns into exit 1, so the proof passes on 3
        # and says what it did not see rather than failing every local repair.
        RUNNER_INCONCLUSIVE = 3

        PROOF_ROOTS = {
          "MASTER" => Operator::GateChain::MASTER,
          "OPENBSD" => File.join(Operator::GateChain::ROOT, "OPENBSD"),
        }.freeze

        # Every commit this runtime delivers opens with it. A baseline outlives
        # a move of origin/main made only of these, because a baseline taken
        # after the pass's own commits would count their failures as old.
        OWN_SUBJECT = "fix_loop:"
        NAMES_SHOWN = 8
        DELIVERY_PATHS_SHOWN = 40

        @baselines = {}
        @lock = Mutex.new

        class << self
          # [held, line]: whether the proof holds, and the sentence that says why.
          def judge(after, baseline)
            count = "proof: #{after.passed} of #{after.total}"
            return [after.ok, "#{count}; no baseline, so green is required: #{after.ok ? "green" : "red"}"] \
              unless baseline&.measured?

            unread = unreadable(after, baseline)
            return [false, "#{count}; #{unread}"] if unread

            added = after.failing - baseline.failing
            worse = worse_rows(after, baseline)
            already = after.failing & baseline.failing
            [added.empty? && worse.empty?, verdict_line(count, already:, added:, worse:)]
          end

          # Every row read is a ratchet counting down, so higher is worse, and a
          # row the baseline did not print was at zero or under its ceiling.
          def worse_rows(after, baseline)
            after.rows.filter_map do |row, value|
              "#{row} #{baseline.rows.fetch(row, 0)} to #{value}" if value > baseline.rows.fetch(row, 0)
            end
          end

          # A suite that crashed, or stopped reaching its summary, names too
          # little to compare, and so cannot hold.
          def unreadable(after, baseline)
            return "a suite crashed before it named its failures" unless after.measured?

            "a suite that finished at baseline did not finish" if after.finished < baseline.finished
          end

          def verdict_line(count, already:, added:, worse:)
            parts = [count]
            parts << "#{already.size} failing already at baseline (#{names(already)})" if already.any?
            parts << "new failures: #{names(added)}" if added.any?
            parts << "worse: #{worse.join(", ")}" if worse.any?
            parts << (already.any? ? "no new failures" : "no failures") if added.empty? && worse.empty?
            parts.join("; ")
          end

          def names(keys)
            sorted = keys.to_a.sort
            shown = sorted.first(NAMES_SHOWN).join(", ")
            sorted.size > NAMES_SHOWN ? "#{shown}, and #{sorted.size - NAMES_SHOWN} more" : shown
          end

          # A baseline stands while origin/main has not moved, or has moved only
          # by this runtime's own commits. A reload onto new MASTER code starts a
          # new process, and so a new baseline.
          def recall(proof, sha:, repo:)
            kept_sha, reading = @lock.synchronize { @baselines[proof] }
            return unless kept_sha && sha
            return reading if kept_sha == sha

            # This checkout is a partial clone, and a commit it lacks would be
            # fetched object by object; unknown is a reason to measure again.
            out, _err, status = Master::Io::Exec.capture3({ "GIT_NO_LAZY_FETCH" => "1" }, "git", "-C", repo, "log",
                                                          "--format=%s", "#{kept_sha}..#{sha}", timeout: 20)
            reading if status.success? && out.lines.all? { |subject| subject.start_with?(OWN_SUBJECT) }
          end

          def remember(proof, sha:, reading:)
            @lock.synchronize { sha ? @baselines[proof] = [sha, reading] : @baselines.delete(proof) }
          end

          def forget_all = @lock.synchronize { @baselines.clear }
        end

        private

        # Before the repair: the same proof on the untouched tree, or the one
        # kept from an earlier pass in this process.
        def proof_baseline(abs)
          return if ENV[PROOF_ENV] == "1"

          name, runner = proof_runner(abs)
          return unless runner

          sha = origin_main
          kept = Proof.recall(name, sha:, repo: Master::REPO_ROOT)
          return kept.tap { Master::Trace::Dmesg.status("gate0", "baseline kept: #{baseline_line(kept)}") } if kept

          log_phase("gate0", "baseline", name) { measure_baseline(name, sha:, runner:) }
        rescue StandardError => e
          raise if Pass::DEFECT_ERRORS.any? { |klass| e.is_a?(klass) }

          Master::Trace::Dmesg.status("gate0", "baseline unmeasured: #{e.class}: #{e.message}")
          nil
        end

        def measure_baseline(name, sha:, runner:)
          reading = Reading.parse(*inside_proof { runner.call })
          Proof.remember(name, sha: (sha if reading.measured?), reading:)
          Master::Trace::Dmesg.status("gate0", "baseline: #{baseline_line(reading)}")
          reading
        end

        def proof_section(abs, baseline = nil)
          return ["proof", "proof skipped: already inside a proof run"] if ENV[PROOF_ENV] == "1"

          _name, runner = proof_runner(abs)
          return ["proof", "no proof command for #{shell_target(abs)} — nothing registered"] unless runner

          ["proof", log_phase("gate0", "proof", nil) do
            ok, out = inside_proof { runner.call }
            held, verdict = Proof.judge(Reading.parse(ok, out), baseline)
            Master::Trace::Dmesg.status("gate0", verdict)
            @failed_stages << "proof" unless held
            [verdict, proof_body(held, out), (deliver_leftovers(abs, verdict) if held)].compact.join("\n")
          end]
        end

        # RAILS proves by `runner.rb --all` (GATE_AUTOFIX=0: the fix loop owns
        # the writes, the proof measures); the other trees prove by their whole
        # suites, which is `bin/operator test`'s mapping, unchanged. Each suite
        # keeps its whole output under its own header, because the failures a
        # baseline compares are named deep in it, not in the last lines.
        def proof_runner(abs)
          chain = Operator::GateChain
          if abs == Master::RAILS_ROOT || abs.start_with?("#{Master::RAILS_ROOT}/")
            return ["rails gates", -> { rails_proof(*chain.rails_gates(scan_only: true)) }]
          end

          tree = PROOF_ROOTS.find { |_name, root| abs == root || abs.start_with?("#{root}/") }&.first
          [tree, -> { suite_proof(chain, tree) }] if tree
        end

        def suite_proof(chain, tree)
          runs = chain.suite_jobs([tree]).map do |name, cmd, dir, env, _tree, unbundled|
            # bin/check prints a passing step's output only when asked, and a
            # suite that passed must still count as one that finished.
            ok, out = chain.capture(*cmd, chdir: dir, env: env.merge("CHECK_VERBOSE" => "1"), unbundled:)
            [name, ok, out]
          end
          framed = runs.flat_map { |name, ok, out| ["proof suite #{name}: #{ok ? "ok" : "FAIL"}", *out] }
          [runs.all? { |_name, ok, _out| ok }, framed]
        end

        def rails_proof(ok, out, status)
          return [ok, out] unless !ok && status == RUNNER_INCONCLUSIVE

          [true, Array(out) + ["proof: no gate failed; the inconclusive gates above measured nothing here " \
                               "(GATE_STRICT_INCONCLUSIVE=1 blocks on them)"]]
        end

        def inside_proof
          previous = ENV[PROOF_ENV]
          ENV[PROOF_ENV] = "1"
          yield
        ensure
          ENV[PROOF_ENV] = previous
        end

        def proof_body(held, out)
          lines = Array(out).map(&:to_s).reject(&:empty?)
          shown = held ? lines.last(6) : lines.last(PROOF_TAIL)
          shown.join("\n") unless shown.empty?
        end

        # What the repair left uncommitted — mostly the observation's
        # mechanical autofix — goes out once the proof holds, as one commit
        # scoped to the target's tree and carrying the proof's verdict. Only in
        # a linked worktree: in the shared checkout a path that changed during
        # the pass may be another session's, and git cannot tell them apart.
        def deliver_leftovers(abs, verdict)
          return unless @start_dirty

          paths = leftover_paths(abs)
          return "delivery: nothing left uncommitted" if paths.empty?
          unless File.file?(File.join(Master::REPO_ROOT, ".git"))
            return "delivery: #{paths.size} file(s) left in the tree; the shared checkout is not a /fix worktree"
          end

          publish(delivery_message(abs, verdict:, paths:), paths)
          line = "delivery: #{repo_git.head} carries #{paths.size} file(s)"
          Master::Trace::Dmesg.status("gate0", line)
          line
        rescue StandardError => e
          stage_failure("delivery", "gate0", e)
        end

        # A rejected push rebases once and retries; a commit still ahead
        # afterwards is a delivery that did not land.
        def publish(message, paths)
          repo_git.commit(message, paths:)
          repo_git.push
          ahead, = repo_git.ahead_behind
          raise "push left #{ahead} commit(s) unpushed" if ahead.positive?
        end

        def leftover_paths(abs)
          tree = abs.delete_prefix("#{Master::REPO_ROOT}/").split("/").first
          return [] unless Operator::GateChain::TREES.include?(tree)

          (repo_git.changed_paths - @start_dirty).select { |path| path.start_with?("#{tree}/") }
                                                 .grep_v(Operator::GateChain::GENERATED)
        end

        def delivery_message(abs, verdict:, paths:)
          tree = abs.delete_prefix("#{Master::REPO_ROOT}/").split("/").first
          listed = paths.first(DELIVERY_PATHS_SHOWN)
          listed << "and #{paths.size - listed.size} more" if paths.size > listed.size
          ["#{OWN_SUBJECT} deliver #{tree}, proof held", "", verdict, "", *listed].join("\n")
        end

        def baseline_line(reading)
          return "unmeasured, a suite crashed before it named its failures" unless reading.measured?

          failing = reading.failing
          line = "#{reading.passed} of #{reading.total}"
          failing.empty? ? "#{line}, green" : "#{line}, #{failing.size} failing (#{Proof.names(failing)})"
        end

        def origin_main
          out, _err, status = Master::Io::Exec.capture3("git", "-C", Master::REPO_ROOT, "rev-parse", "origin/main")
          status.success? ? out.strip : nil
        end

        def repo_git = @repo_git ||= Master::Io::GitOperations.new(Master::REPO_ROOT)
      end
    end
  end
end
