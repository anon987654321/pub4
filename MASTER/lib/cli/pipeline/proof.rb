# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "set"
require_relative "../../operator/check_chain"
require_relative "proof/reading"
require_relative "proof/affected"
require_relative "proof/rails_apps"
require_relative "../../fix/check_focus"
require_relative "../../fix/rails_app"

module Master
  module CLI
    class Pipeline
      # The proof a writing pass owes, measured against the same proof run on
      # the untouched tree before the repair.
      #
      # Main is rarely green on a shared repository: other sessions' work in
      # flight, and ceilings an approved design change went over, keep some
      # check or test red whatever /fix does. A proof that demanded green
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

        # runner.rb exits 3 when no check failed and some measured nothing — off
        # the deploy host that is deploy_drift's stamps, and the rendered half
        # when Chrome or the apps are absent. A normal contribution check may
        # report that state without blocking, but /fix cannot call an unmeasured
        # proof green. Set strict inconclusive handling only inside the proof
        # and restore the caller's policy afterwards.
        RUNNER_INCONCLUSIVE = 3
        STRICT_ENV = "CHECK_STRICT_INCONCLUSIVE"

        PROOF_ROOTS = {
          "MASTER" => ::Operator::CheckChain::MASTER,
          "OPENBSD" => File.join(::Operator::CheckChain::ROOT, "OPENBSD"),
          "STUDIO" => File.join(::Operator::CheckChain::ROOT, "STUDIO"),
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
          kept = Proof.recall(name, sha:, repo: Master::REPO_ROOT) || stored_baseline(abs, name)
          return kept.tap { Master::Trace::Dmesg.status("check0", "baseline kept: #{baseline_line(kept)}") } if kept
          return if narrow_known(abs, nil)

          log_phase("check0", "baseline", name) { measure_baseline(name, sha:, runner:) }.tap do |reading|
            store_baseline(abs, name:, reading:)
            Affected.note_known_red("MASTER", reading) if abs == PROOF_ROOTS["MASTER"]
          end
        rescue StandardError => e
          raise if Pass::DEFECT_ERRORS.any? { |klass| e.is_a?(klass) }

          Master::Trace::Dmesg.status("check0", "baseline unmeasured: #{e.class}: #{e.message}")
          nil
        end

        # The proof baseline was kept only in this process, so every /fix ran the whole suite again
        # before its first edit. It is now kept on disk under the target tree's content: the same tree
        # (committed and uncommitted bytes), proof and target reuse it; any change measures afresh.
        # MASTER_PROOF_STORE=0 turns it off, as the tests do.
        PROOF_STORE = File.join(Master::ROOT, ".master", "proof_baselines")

        def store_dir = ENV.fetch("MASTER_PROOF_STORE_DIR", PROOF_STORE)

        def store_path(abs, name)
          return if ENV["MASTER_PROOF_STORE"] == "0"

          tree = abs.delete_prefix("#{Master::REPO_ROOT}/").split("/").first
          content = ::Operator::CheckChain.baseline_key(tree, trees: [tree])
          key = Digest::SHA256.hexdigest([content, name, abs].join("\0"))
          File.join(store_dir, "#{key}.json")
        end

        def stored_baseline(abs, name)
          path = store_path(abs, name)
          return unless path && File.file?(path)

          stored = JSON.parse(File.read(path, encoding: "UTF-8"))
          Master::Fix::CheckFocus.note(stored.fetch("named"))
          Reading.from_stored(stored.fetch("reading"))
        rescue StandardError => e
          Master::Trace::Dmesg.status("check0", "stored baseline unreadable, measuring again: #{e.class}")
          nil
        end

        def store_baseline(abs, name:, reading:)
          path = store_path(abs, name)
          return unless path && reading&.measured?

          FileUtils.mkdir_p(File.dirname(path))
          stored = { "reading" => reading.to_stored, "named" => Master::Fix::CheckFocus.named.to_a }
          File.write(path, JSON.generate(stored))
        end

        def measure_baseline(name, sha:, runner:)
          ok, out = inside_proof { runner.call }
          Master::Fix::CheckFocus.note(out) unless ok
          reading = Reading.parse(ok, out)
          Proof.remember(name, sha: (sha if reading.measured?), reading:)
          Master::Trace::Dmesg.status("check0", "baseline: #{baseline_line(reading)}")
          reading
        end

        def proof_section(abs, baseline = nil)
          return ["proof", "proof skipped: already inside a proof run"] if ENV[PROOF_ENV] == "1"

          known = narrow_known(abs, baseline)
          tests = known && Affected.tests_for(repair_paths)
          _name, runner = tests ? affected_runner(tests) : proof_runner(abs)
          return ["proof", "no proof command for #{shell_target(abs)} — nothing registered"] unless runner

          narrow = known && (tests || baseline.nil?)
          judge = narrow ? ->(r) { Affected.judge(r, known) } : ->(r) { Proof.judge(r, baseline) }
          ["proof", log_phase("check0", "proof", nil) { proof_verdict(abs, runner:, judge:, whole: tests.nil?) }]
        end

        def proof_verdict(abs, runner:, judge:, whole:)
          ok, out = inside_proof { runner.call }
          reading = Reading.parse(ok, out)
          held, verdict = judge.call(reading)
          record_proof(abs, reading, verdict:, whole: whole && held)

          fail_stage("proof", verdict) unless held
          [verdict, proof_body(held, out), (deliver_leftovers(abs, verdict) if held)].compact.join("\n")
        end

        # A whole suite that held is what the tree now leaves red, for the next narrow proof to judge by.
        def record_proof(abs, reading, verdict:, whole:)
          Affected.note_known_red("MASTER", reading) if whole && abs == PROOF_ROOTS["MASTER"]
          hard, soft = Master::Fix::CheckTiers.split(reading.failing, target: abs)
          @proof = { verdict:, hard:, soft:, unmeasured: reading.unmeasured.sort }
          Master::Trace::Dmesg.status("check0", verdict)
        end

        # What the repair changed under this pass's root, its own and anything else written since.
        def repair_paths = @repair_before ? Array(git.paths_since(@repair_before)) : []

        # The pass's root is MASTER, so git.paths_since never lists a RAILS file; the app proof
        # reads what changed from the repository root.
        def rails_repair_paths
          @repair_before ? Array(repo_git.paths_since(@repair_before)).grep(%r{\ARAILS/}) : []
        end

        # A whole-MASTER pass proves with the tests that name what it changed when it has what was red
        # before to judge them by: its baseline if one was kept, else the tree's known-red record
        # (Proof::Affected). Nil keeps the whole suite.
        def narrow_known(abs, baseline)
          return unless Affected.enabled? && abs == PROOF_ROOTS["MASTER"]
          return Affected::Known.new(failing: baseline.failing, rows: baseline.rows) if baseline&.measured?

          Affected.known_red("MASTER")
        end

        def affected_runner(tests)
          chain = ::Operator::CheckChain
          script = "ARGV.each { |path| require File.expand_path(path) }"
          ["MASTER tests for the changed files", lambda do
            ok, out = chain.capture(chain::RUBY, "-Itest", "-e", script, *tests, chdir: chain::MASTER)
            [ok, ["proof suite MASTER affected (#{tests.size} files): #{ok ? "ok" : "FAIL"}", *Array(out)]]
          end]
        end

        # RAILS proves by `runner.rb --all` (CHECK_AUTOFIX=0: the fix loop owns
        # the writes, the proof measures); the other trees prove by their whole
        # suites, which is `bin/operator test`'s mapping, unchanged. Each suite
        # keeps its whole output under its own header, because the failures a
        # baseline compares are named deep in it, not in the last lines.
        def proof_runner(abs)
          chain = ::Operator::CheckChain
          if Master::Fix::RailsApp.tree_target?(abs, repo_root: Master::REPO_ROOT)
            # The rails checks are the "source" stage. A run that named its stages
            # (MASTER_FIX_CHECK_STAGES) without it asked for a source-only proof, and with
            # no apps up the rendered half could only report red.
            return unless chain.verification_stage?("source")

            return ["rails checks", -> {
              held, out = rails_proof(*chain.rails_checks(scan_only: true, strict_inconclusive: ENV[PROOF_ENV] == "1"))
              apps_held, apps_out = RailsApps.prove(rails_repair_paths, before: @repair_before)
              [held && apps_held, Array(out) + apps_out]
            }]
          end

          tree, root = PROOF_ROOTS.find { |_name, dir| abs == dir || abs.start_with?("#{dir}/") }
          return unless tree
          # A narrower target proves with the tests that map to it, as `bin/operator test` does;
          # the whole suites answer for the whole tree. A file or directory took the full suites
          # of its tree for every pass, thirty minutes to repair one file.
          return [tree, -> { suite_proof(chain, tree) }] if abs == root

          ["#{tree} tests for #{File.basename(abs)}", -> { targeted_proof(chain, abs) }]
        end
        public :proof_runner

        # No test maps to the path is not a failure of the repair: it is a target with no proof to
        # offer, and says so in the reading.
        UNMAPPED = /no suite maps to/

        def targeted_proof(chain, abs)
          ok, out = chain.capture(chain::RUBY, File.join(chain::MASTER, "bin", "operator"), "test", abs,
                                  chdir: chain::MASTER, env: { "CHECK_VERBOSE" => "1" })
          lines = Array(out)
          held = ok || lines.any? { |line| line.to_s.match?(UNMAPPED) }
          [held, ["proof tests for #{abs}: #{ok ? "ok" : "FAIL"}", *lines]]
        end

        def suite_proof(chain, tree)
          # A suite runs minutes with its output captured; the heartbeat keeps
          # the terminal saying so, as it does for the rails checks.
          runs = ::Operator::CheckHeartbeat.around("#{tree} suites") do |_progress|
            chain.suite_jobs([tree]).map do |name, cmd, dir, env, _tree, unbundled|
              # bin/check prints a passing step's output only when asked, and a
              # suite that passed must still count as one that finished.
              ok, out = chain.capture(*cmd, chdir: dir, env: env.merge("CHECK_VERBOSE" => "1"), unbundled:)
              [name, ok, out]
            end
          end
          framed = runs.flat_map { |name, ok, out| ["proof suite #{name}: #{ok ? "ok" : "FAIL"}", *out] }
          [runs.all? { |_name, ok, _out| ok }, framed]
        end

        def rails_proof(ok, out, status)
          return [ok, out] unless !ok && status == RUNNER_INCONCLUSIVE

          if ENV[STRICT_ENV] == "1"
            [false, Array(out) + ["proof: checks measured nothing and #{STRICT_ENV}=1 forbids passing on that"]]
          else
            [true, Array(out) + ["proof: no check failed; the inconclusive checks above measured nothing here " \
                                 "(#{STRICT_ENV}=1 blocks on them)"]]
          end
        end

        def inside_proof
          previous = ENV[PROOF_ENV]
          previous_strict = ENV[STRICT_ENV]
          ENV[PROOF_ENV] = "1"
          ENV[STRICT_ENV] = "1"
          yield
        ensure
          ENV[PROOF_ENV] = previous
          ENV[STRICT_ENV] = previous_strict
        end

        def proof_body(held, out)
          lines = Array(out).map(&:to_s).reject(&:empty?)
          shown = held ? lines.last(6) : lines.last(PROOF_TAIL)
          shown.join("\n") unless shown.empty?
        end

        # What the repair left uncommitted — mostly the observation's
        # mechanical autofix — goes out once the proof holds, as one commit
        # scoped to the target's tree and carrying the proof's verdict. In the
        # shared checkout only the autofix's own writes go, matched by content.
        def deliver_leftovers(abs, verdict)
          return unless @start_dirty

          paths = leftover_paths(abs)
          return "delivery: nothing left uncommitted" if paths.empty?

          paths = attributed(paths) unless File.file?(File.join(Master::REPO_ROOT, ".git"))
          return "delivery: nothing in the shared checkout is attributably this run's" if paths.empty?

          publish(delivery_message(abs, verdict:, paths:), paths)
          line = "delivery: #{repo_git.head} carries #{paths.size} file(s)"
          Master::Trace::Dmesg.status("check0", line)
          line
        rescue StandardError => e
          stage_failure("delivery", "check0", e)
        end

        # In the shared checkout a changed path may be another session's. Only files the autofix wrote,
        # still holding exactly the bytes it wrote, are this run's to deliver.
        def attributed(paths)
          paths.select { |path| Master::Fix::AutofixGuard.still_as_written?(File.join(Master::REPO_ROOT, path)) }
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
          return [] unless ::Operator::CheckChain::TREES.include?(tree)

          (repo_git.changed_paths - @start_dirty).select { |path| path.start_with?("#{tree}/") }
                                                 .grep_v(::Operator::CheckChain::GENERATED)
        end

        def delivery_message(abs, verdict:, paths:)
          tree = abs.delete_prefix("#{Master::REPO_ROOT}/").split("/").first
          listed = paths.first(DELIVERY_PATHS_SHOWN)
          listed << "and #{paths.size - listed.size} more" if paths.size > listed.size
          ["#{OWN_SUBJECT} deliver #{tree}, proof held", "", verdict, "", *listed].join("\n")
        end

        def baseline_line(reading)
          return "INCONCLUSIVE, baseline suite did not finish" unless reading.measured?

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
