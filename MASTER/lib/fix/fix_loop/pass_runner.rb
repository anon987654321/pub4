# frozen_string_literal: true

require "digest"
require "fileutils"
require "open3"
require "set"
require "time"
require_relative "pass_runner/fast_stage"
require_relative "pass_runner/llm_stage"
require_relative "pass_runner/stagnation_detection"
require_relative "pass_runner/evidence_stage"
require_relative "pass_runner/stream_stage"
require_relative "structural_stage"
require_relative "../transaction"
require_relative "../resource_budget"

module Master
  module Fix
    class FixLoop
      class PassRunner
        # The model-repair stage's share of one pass; MASTER_FIX_PASS_BUDGET_S
        # widens it for slow lanes, as MASTER_FIX_RUN_BUDGET_S does the run.
        PASS_BUDGET_SECONDS = Integer(ENV.fetch("MASTER_FIX_PASS_BUDGET_S", 8 * 60))

        PassResult = Struct.new(:status, :message, :consecutive_clean, keyword_init: true)

        include FastStage
        include LlmStage
        include StagnationDetection
        include EvidenceStage
        include StreamStage
        include StructuralStage

        def initialize(bus:, committer:, conflict_resolver:, llm_router:, rollback:, root:,
                       rules:, agent:, scanner:, learnings:, preamble:,
                       clean_runs_required:, plateau_window:, ground_truth: nil, homeostat: nil, council: nil,
                       visual_pass: nil, opportunity_pass: nil)
          @bus = bus
          @committer = committer
          @conflict_resolver = conflict_resolver
          @llm_router = llm_router
          @rollback = rollback
          @root = root
          @resource_budget = ResourceBudget.new(root:)
          @agent = agent
          @scanner = scanner
          @learnings = learnings
          @preamble = preamble
          @rule_order = RuleOrder.new(rules:, learnings:, bus:, root:)
          take_limits(clean_runs_required:, plateau_window:, ground_truth:, homeostat:, council:, visual_pass:, opportunity_pass:)
        end

        # What a pass is judged by, apart from the collaborators it runs through:
        # when it may stop, when it has stopped moving, and who else gets a say.
        def take_limits(clean_runs_required:, plateau_window:, ground_truth:, homeostat:, council:, visual_pass:, opportunity_pass:)
          @clean_runs_required = clean_runs_required
          @plateau_window = plateau_window
          @violation_counts = Hash.new(0)
          @rule_recurrence = Hash.new(0)
          @ground_truth = ground_truth
          @homeostat = homeostat
          @council = council
          @visual_pass = visual_pass
          @opportunity_pass = opportunity_pass
          @ground_truth_failures = 0
        end

        def violations(files) = resolve_violations(files.flat_map { |path| violations_for(path) })

        def violations_for(path)
          return [] unless File.exist?(path)

          result = Master::Result.wrap(@scanner.scan(path))
          return skip_unreadable(path, result) if !result.ok? && result.category == :validation
          raise "fix scan failed for #{path}: #{result.message}" unless result.ok?

          findings = result.value!
          @bus&.publish("fix_loop:scan_progress", file: path.delete_prefix("#{@root}/"), count: findings.size) if findings.any?
          findings.select { |finding| Severity.at_least?(finding.fetch(:severity, :warning), :warning) }
                  .map { |finding| Violation.from_finding(finding, file: path.delete_prefix("#{@root}/")) }
        end

        def resolve_violations(raw)
          @conflict_resolver.filter_findings(raw.map(&:to_h)).map { |row| row.transform_keys(&:to_sym) }
        end

        def skip_unreadable(path, result)
          Master::Trace::Dmesg.once("fix0", "skipped #{path.delete_prefix("#{@root}/")}, #{result.message.split(":").first}")
          []
        end

        def run_pass(files:, target:, pass:, deadline:, transaction_id:, history:, seen_snapshots:,
                     recurring_violations:, consecutive_clean:)
          pass_mtimes = mtimes(files)
          start_pass_transaction(files:, target:, pass:, transaction_id:)
          found, streamed = observe_pass(files, target, pass, deadline)

          visual, opportunities, found = merge_evidence_findings(target:, files:, pass:, found:)
          return evidence_abort_result(visual, opportunities) if found.empty? && (visual&.err? || opportunities&.err?)

          found, shed = supplement_with_improvements(found, pass:, files:, deadline:, consecutive_clean:)
          return shed if shed
          return clean_pass_result(files, pass_mtimes, pass, consecutive_clean) if found.empty?
          return plateau_result if stagnant?(history, seen_snapshots, recurring_violations, found, pass)

          # A reload skips the rule stage: it would ask the model about the whole
          # scan on code that is already out of date.
          dispatch_llm_stages(unstreamed(found, streamed), files, pass, deadline, visual) unless CodeWatch.requested?
          delivered = deliver_pass(found, files, pass)
          return delivered unless CodeWatch.requested? && delivered.status == :continue

          PassResult.new(status: :reloading, consecutive_clean: 0, message: "MASTER changed on origin/main")
        rescue StandardError
          @committer.abort_transaction!
          raise
        ensure
          @visual_pass&.cleanup
        end

        def finish_transaction(files, pass, result)
          delivery = @committer.finish_transaction("fix_loop: clean [pass #{pass}]", owned_paths: files)
          return PassResult.new(status: :delivery_failed, consecutive_clean: 0, message: delivery.message) if delivery.err?

          result
        end

        def abort_transaction(result = nil)
          @committer.abort_transaction!
          result
        end

        private

        # A pass that needs a person stops before delivery; otherwise its
        # transaction is committed, and a delivery that fails is the result.
        def deliver_pass(found, files, pass)
          if @human_decision_required
            @committer.abort_transaction!
            return PassResult.new(status: :human_decision, consecutive_clean: 0, message: "human decision required before continuing autofix")
          end
          delivery = @committer.finish_transaction("fix_loop: pass #{pass}", findings: found, owned_paths: files)
          return PassResult.new(status: :delivery_failed, consecutive_clean: 0, message: delivery.message) if delivery.err?

          PassResult.new(status: :continue, consecutive_clean: 0)
        end

        def clean_pass_result(files, pass_mtimes, pass, consecutive_clean)
          result = handle_clean_pass(files, pass_mtimes, pass, consecutive_clean)
          return abort_transaction(result) if result.status == :validation_failed

          finish_transaction(files, pass, result)
        end

        def start_pass_transaction(files:, target:, pass:, transaction_id:)
          boundary_scope = Master::Phoenix.scope_for(target, root: @root)
          @committer.baseline!(scope: boundary_scope)
          @bus&.publish("fix_loop:boundary_scope", target:, boundaries: boundary_scope)
          transaction = Transaction.new(root: @root, paths: files, id: transaction_id, bus: @bus)
          @committer.begin_transaction!(transaction)
          @bus&.publish("fix_loop:pass_start", pass:, target:, file_count: files.size)
        end

        def plateau_result
          abort_transaction
          PassResult.new(status: :plateau, consecutive_clean: 0)
        end

        # The council is asked once per clean streak, on its first pass; a
        # confirming pass after it found nothing would ask the same question
        # again. Returns [found, early] -- early is the shed-resources
        # PassResult to return immediately, or nil to keep going with the
        # (possibly still empty) found.
        def supplement_with_improvements(found, pass:, files:, deadline:, consecutive_clean:)
          return [found, nil] unless found.empty? && consecutive_clean.zero?

          resources = @resource_budget.measure
          if @resource_budget.critical?(resources)
            @committer.abort_transaction!
            @bus&.publish("fix_loop:model_work_shed", pass:, reasons: resources[:reasons], values: resources[:values])
            Master::Trace::Dmesg.status("fix0", "pass #{pass}, improvement review shed: #{resources[:reasons].join("; ")}")
            shed = PassResult.new(status: :plateau, consecutive_clean: 0, message: "model work shed: #{resources[:reasons].join("; ")}")
            return [found, shed]
          end

          [found + Array(@council&.improve(files:, pass:, deadline:)), nil]
        end

        # found may now hold three kinds of finding -- ordinary rule
        # violations, council-selected improvements, and rendered-visual
        # findings -- each routed to the stage that knows how to fix it. A
        # shed here (unlike supplement_with_improvements above) does not
        # abort: found is non-empty, so the transaction still delivers
        # whatever the fast/observation stages already produced.
        def dispatch_llm_stages(found, files, pass, deadline, visual)
          resources = @resource_budget.measure
          if @resource_budget.critical?(resources)
            @bus&.publish("fix_loop:model_work_shed", pass:, reasons: resources[:reasons], values: resources[:values])
            Master::Trace::Dmesg.status("fix0", "pass #{pass}, model work shed: #{resources[:reasons].join("; ")}")
            return
          end

          @homeostat&.observe(:llm_call)
          excluded = [VisualPass::RULE_ID, OpportunityPass::RULE_ID, CouncilRound::IMPROVEMENT_RULE_ID]
          source_found = unremembered(found.reject { |v| excluded.include?(v[:rule].to_s) })
          improvement_found = found.select { |v| v[:rule].to_s == CouncilRound::IMPROVEMENT_RULE_ID }
          visual_found = found.select { |v| v[:rule].to_s == VisualPass::RULE_ID }
          opportunity_found = found.select { |v| v[:rule].to_s == OpportunityPass::RULE_ID }
          council = @council&.run(files: files_with_violations(source_found, files), pass:, deadline:) if source_found.any?
          run_llm_stage(source_found, files, pass, deadline, council:) if source_found.any?
          run_improvement_stage(improvement_found, pass:, files:, deadline:) if improvement_found.any?
          run_opportunity_stage(opportunity_found, files, pass, deadline, council:) if opportunity_found.any?
          run_visual_stage(visual_found, pass:, image: visual&.value!&.fetch(:image, nil), files:, deadline:) if visual_found.any?
        end

        def run_fast_stage(files, pass)
          fixed = fast_pass(files)
          @committer.commit_if_dirty("fix_loop: fast-fix [pass #{pass}]", owned_paths: files) if fixed > 0
          fixed
        end

        def observe_pass(files, target, pass, deadline)
          run_fast_stage(files, pass)
          found, streamed = streaming_observation(files, target, pass, deadline)
          [files.empty? ? found : found + structural_findings(files:), streamed]
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
          return 0 unless llm_stage_resources_ok?(pass)

          pass_deadline = [Time.now + PASS_BUDGET_SECONDS, deadline].min
          llm_fixed = llm_pass(violations: found, files:, pass:, deadline: pass_deadline, council:)
          Master::Trace::Dmesg.status("fix0", "pass #{pass}, #{llm_fixed} of #{Master::Trace::Dmesg.counted(found.size, "violation")} fixed")
          @committer.commit_if_dirty("fix_loop: llm-fix [pass #{pass}]", findings: found, owned_paths: files) if llm_fixed > 0
          track_recurrence(found)
          llm_fixed
        end

        def llm_stage_resources_ok?(pass)
          resources = @resource_budget.measure
          if @resource_budget.critical?(resources)
            @bus&.publish("fix_loop:llm_skipped", pass:, reason: "resource_critical",
                          reasons: resources[:reasons], values: resources[:values])
            Master::Trace::Dmesg.status("fix0", "pass #{pass}, model fixes shed: #{resources[:reasons].join("; ")}")
            return false
          end
          @bus&.publish("fix_loop:resource_warning", pass:, reasons: resources[:reasons]) if @resource_budget.warning?(resources)
          true
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
      end
    end
  end
end
