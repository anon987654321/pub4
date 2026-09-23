# frozen_string_literal: true

require "digest"
require "fileutils"
require "open3"
require "set"
require "time"
require_relative "pass_runner/fast_stage"
require_relative "pass_runner/llm_stage"
require_relative "pass_runner/stagnation_detection"

module Master
  module Fix
    class FixLoop
      class PassRunner
        PASS_BUDGET_SECONDS = 8 * 60

        PassResult = Struct.new(:status, :message, :consecutive_clean, keyword_init: true)

        include FastStage
        include LlmStage
        include StagnationDetection

        def initialize(bus:, committer:, loop_scanner:, llm_router:, rollback:, root:,
                       rules:, agent:, scanner:, learnings:, preamble:,
                       clean_runs_required:, plateau_window:, ground_truth: nil, homeostat: nil, council: nil,
                       rendered_review: nil)
          @bus = bus
          @committer = committer
          @loop_scanner = loop_scanner
          @llm_router = llm_router
          @rollback = rollback
          @root = root
          @agent = agent
          @scanner = scanner
          @learnings = learnings
          @preamble = preamble
          @rule_order = RuleOrder.new(rules:, learnings:, bus:, root:)
          take_limits(clean_runs_required:, plateau_window:, ground_truth:, homeostat:, council:, rendered_review:)
        end

        # What a pass is judged by, apart from the collaborators it runs through:
        # when it may stop, when it has stopped moving, and who else gets a say.
        def take_limits(clean_runs_required:, plateau_window:, ground_truth:, homeostat:, council:, rendered_review:)
          @clean_runs_required = clean_runs_required
          @plateau_window = plateau_window
          @violation_counts = Hash.new(0)
          @rule_recurrence = Hash.new(0)
          @ground_truth = ground_truth
          @homeostat = homeostat
          @council = council
          @rendered_review = rendered_review
          @ground_truth_failures = 0
        end

        def violations(files) = @loop_scanner.violations(files)

        def run_pass(files:, target:, pass:, deadline:, history:, seen_snapshots:,
                     recurring_violations:, consecutive_clean:)
          pass_mtimes = mtimes(files)
          @committer.baseline!
          @bus&.publish("fix_loop:pass_start", pass:, target:, file_count: files.size)

          run_fast_stage(files, pass)
          found = run_observation_stage(files, target)

          visual = run_rendered_review(target:, files:, pass:)
          if visual&.err?
            return PassResult.new(
              status: :plateau,
              consecutive_clean: 0,
              message: visual.message,
            ) if found.empty?
          end

          visual_findings = visual&.ok? ? Array(visual.value![:findings]) : []
          found = found + visual_findings

          # A clean deterministic/rendered read is an absence of findings, not proof that
          # the artifact cannot be improved. Ask the same Council used during a manual review
          # once at the start of a clean streak; the following pass verifies whatever changed.
          if found.empty? && consecutive_clean.zero?
            improvements = @council&.improve(files:, pass:, deadline:)
            found.concat(Array(improvements))
          end

          return handle_clean_pass(files, pass_mtimes, pass, consecutive_clean) if found.empty?
          return PassResult.new(status: :plateau, consecutive_clean: 0) if stagnant?(history, seen_snapshots, recurring_violations, found, pass)

          @homeostat&.observe(:llm_call)
          # Source findings use the registered rule path. Improvement and rendered findings
          # already came through their respective Councils and therefore go straight into the
          # same RuleLoop without convening a second council for the same pass.
          source_found = found.reject { |v| [RenderedReview::RULE_ID, CouncilRound::IMPROVEMENT_RULE_ID].include?(v[:rule].to_s) }
          improvement_found = found.select { |v| v[:rule].to_s == CouncilRound::IMPROVEMENT_RULE_ID }
          rendered_found = found.select { |v| v[:rule].to_s == RenderedReview::RULE_ID }
          council = @council&.run(files: files_with_violations(source_found, files), pass:, deadline:) if source_found.any?
          run_llm_stage(source_found, files, pass, deadline, council:) if source_found.any?
          run_improvement_stage(improvement_found, pass:, files:, deadline:) if improvement_found.any?
          run_rendered_stage(rendered_found, pass:, image: visual.value![:image], files:, deadline:) if rendered_found.any?
          PassResult.new(status: :continue, consecutive_clean: 0)
        ensure
          @rendered_review&.cleanup
        end

        private

        def run_improvement_stage(findings, pass:, files:, deadline:)
          return 0 if findings.empty? || Time.now >= deadline

          rule = CouncilRound::IMPROVEMENT_RULE.new(CouncilRound::IMPROVEMENT_RULE_ID)
          loop = RuleLoop.new(
            rule:,
            agent: @agent,
            scanner: @scanner,
            root: @root,
            bus: @bus,
            learnings: @learnings,
            committer: @committer,
          )
          loop.injected_preamble = [
            @preamble,
            "These changes were selected by the Council as anchored improvement opportunities. Preserve behavior and make the smallest evidence-backed repair.",
          ].join("\n\n")
          result = loop.run_once(files, external_violations: findings)
          @bus&.publish("fix_loop:improvement_fix", pass:, findings: findings.size, fixed: result[:fixed].to_i)
          result[:fixed].to_i
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "pass_runner.improvement_stage", event_bus: @bus)
          0
        end
        def run_rendered_review(target:, files:, pass:)
          return unless @rendered_review
          return unless @rendered_review.applicable?(target)

          @rendered_review.run(target:, files:, pass:)
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "pass_runner.rendered_review", event_bus: @bus)
          Result.err("rendered visual review: INCONCLUSIVE — #{e.class}: #{e.message}", category: :inconclusive)
        end

        def run_rendered_stage(findings, pass:, image:, files:, deadline:)
          return 0 if Time.now >= deadline

          rule = RenderedReview::RULE.new(RenderedReview::RULE_ID)
          loop = RuleLoop.new(
            rule:,
            agent: @agent,
            scanner: @scanner,
            root: @root,
            bus: @bus,
            learnings: @learnings,
            committer: @committer,
          )
          loop.injected_preamble = [
            @preamble,
            "The following findings came from the real rendered browser. " \
              "Use the attached screenshot as evidence. Preserve accessibility, semantics and responsive behavior.",
          ].join("\n\n")
          result = loop.run_once(files, external_violations: findings, image:)
          @bus&.publish("fix_loop:rendered_fix", pass:, findings: findings.size, fixed: result[:fixed].to_i)
          result[:fixed].to_i
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "pass_runner.rendered_stage", event_bus: @bus)
          0
        end

        def run_fast_stage(files, pass)
          fixed = fast_pass(files)
          @committer.commit_if_dirty("fix_loop: fast-fix [pass #{pass}]", owned_paths: files) if fixed > 0
          fixed
        end

        def run_observation_stage(files, target)
          violations(files).tap { |v| emit_topology(v, target) }
        end

        # The council reads what the violations point at, not the whole target.
        def files_with_violations(found, files)
          named = found.filter_map { |violation| violation[:file].to_s }.uniq.select { |path| File.file?(path) }
          named.empty? ? files.first(CouncilRound::FILES_PER_ROUND) : named
        end

        def run_llm_stage(found, files, pass, deadline, council: nil)
          if circuit_open?
            @bus&.publish("fix_loop:llm_skipped", pass:, reason: "circuit_open", open: open_breakers)
            Master::Trace::Dmesg.status("fix0", "pass #{pass}, model fixes skipped, circuit open for #{open_breakers.join(", ")}")
            return 0
          end
          if (avg = system_load_avg) && avg > Ops::ProcessBudget.config.dig("load", "load_avg_1m", "crit").to_f
            @bus&.publish("fix_loop:llm_skipped", pass:, reason: "load_shed", load: avg)
            Master::Trace::Dmesg.status("fix0", "pass #{pass}, model fixes skipped, load #{avg}")
            sleep 60
            return 0
          end
          pass_deadline = [Time.now + PASS_BUDGET_SECONDS, deadline].min
          llm_fixed = llm_pass(violations: found, files:, pass:, deadline: pass_deadline, council:)
          Master::Trace::Dmesg.status("fix0", "pass #{pass}, #{llm_fixed} of #{Master::Trace::Dmesg.counted(found.size, "violation")} fixed")
          @committer.commit_if_dirty("fix_loop: llm-fix [pass #{pass}]", findings: found, owned_paths: files) if llm_fixed > 0
          track_recurrence(found)
          llm_fixed
        end

        # A reading with no violations is not a finished tree: the ground truth
        # is asked whether the files on disk are what the loop thinks it wrote.
        # One disagreement is a pass that repeats; the same disagreement over
        # and over is a repair the tree refuses, and calling that clean is the
        # false completion this loop exists to refuse.
        def handle_clean_pass(files, pass_mtimes, pass, consecutive_clean)
          ground_truth = ground_truth_violations(files)
          unless ground_truth.empty?
            @ground_truth_failures += 1
            @bus&.publish("fix_loop:ground_truth_failed", pass:, violations: ground_truth.size,
                                                          consecutive: @ground_truth_failures)
            status = @ground_truth_failures >= @clean_runs_required ? :validation_failed : :continue
            refused = "#{ground_truth.size} file(s) failed the ground truth after #{pass} pass(es)"
            return PassResult.new(status:, consecutive_clean: 0, message: refused)
          end
          @ground_truth_failures = 0
          @bus&.publish("fix_loop:ground_truth_ok", pass:)
          unless quiescent?(files, pass_mtimes)
            @bus&.publish("fix_loop:quiesce_wait", pass:)
            return PassResult.new(status: :continue, consecutive_clean: 0)
          end
          clean_count = consecutive_clean + 1
          @bus&.publish("fix_loop:clean", pass:, consecutive_clean: clean_count)
          @homeostat&.observe(:llm_success)
          status = clean_count >= @clean_runs_required ? :clean : :continue
          PassResult.new(status:, message: "clean after #{pass} pass(es)", consecutive_clean: clean_count)
        end

        def ground_truth_violations(files)
          return [] unless @ground_truth

          files.filter_map do |path|
            next unless File.exist?(path)

            result = @ground_truth.assert_fresh!(path, reason: "claim_task_complete")
            next if result.ok?

            { rule: "GROUND_TRUTH", file: path.delete_prefix("#{@root}/"), line: 0, message: result.message }
          end
        end

        def mtimes(files) = files.to_h { |p| [p, File.exist?(p) ? File.mtime(p).to_f : nil] }

        def quiescent?(files, before)
          mtimes(files) == before
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "PassRunner.quiescent?")
          false
        end

        def emit_topology(found, target)
          by_mod = found.group_by { |v| v[:file].to_s.split("/").first(3).join("/") }.transform_values(&:size)
          @bus&.publish("codebase:topology", {
            timestamp: Time.now.utc.iso8601,
            target: target.delete_prefix("#{@root}/"),
            total_violations: found.size,
            any_dirty: found.any?,
            modules: by_mod.map { |path, count| { path:, violations: count } },
          })
        end

        def track_recurrence(found)
          tally = found.group_by { |v| v[:rule].to_s }.transform_values(&:size)
          tally.each do |rule_id, _|
            @rule_recurrence[rule_id] += 1
            next unless @rule_recurrence[rule_id] >= 3
            @rule_recurrence.delete(rule_id)
            sample = found.select { |v| v[:rule].to_s == rule_id }.first(5)
            @bus&.publish("fix_loop:soul_proposal", root: @root, rule: rule_id, sample:)
            append_improvement(rule_id, sample)
          end
          (@rule_recurrence.keys - tally.keys).each { |k| @rule_recurrence.delete(k) }
        end

        def append_improvement(rule_id, sample)
          files = sample.map { |v| v[:file] }.uniq.first(3).join(", ")
          @bus&.publish("loop:recurrence", rule: rule_id, files:, at: Time.now.utc.iso8601)
          line = "#{Time.now.utc.strftime("%Y-%m-%d %H:%M")} #{rule_id}: recurring in #{files}\n"
          # runtime/rsi_improvements.md is Ledger::Feedback's, written from the
          # soul_proposal event above; writing it here too put every line in twice.
          path = File.join(@root, "runtime", "improvements.md")
          FileUtils.mkdir_p(File.dirname(path))
          File.open(path, "a") { |f| f.write(line) }
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "fix_loop.append_improvement", event_bus: @bus, rule_id:)
        end

        def circuit_open? = @llm_router.circuit_open?
        def open_breakers = @llm_router.open_breakers

        def system_load_avg
          out, _, st = Master::Io::Exec.capture3("/sbin/sysctl", "-n", "vm.loadavg")
          return unless st.success?
          out.to_s[/\d+(?:\.\d+)?/]&.to_f
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "PassRunner.system_load_avg")
          nil
        end
      end
    end
  end
end
