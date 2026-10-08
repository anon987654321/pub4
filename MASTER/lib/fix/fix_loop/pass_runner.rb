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
require_relative "../scan_phase"
require_relative "../transaction"
require_relative "../resource_budget"
require_relative "../wishlist"
require_relative "../../review/scan/law_health"

module Master
  module Fix
    class FixLoop
      class PassRunner
        PASS_BUDGET_SECONDS = Integer(ENV.fetch("MASTER_FIX_PASS_BUDGET_S", 8 * 60))

        PassResult = Struct.new(:status, :message, :consecutive_clean, keyword_init: true)

        include FastStage
        include LlmStage
        include StagnationDetection
        include EvidenceStage
        include StreamStage
        include StructuralStage

        def initialize(bus:, committer:, conflict_resolver:, llm_router:, root:,
                       laws:, agent:, scanner:, learnings:, preamble:,
                       clean_runs_required:, plateau_window:, ground_truth: nil, homeostat: nil, council: nil,
                       visual_pass: nil, opportunity_pass: nil, preflight: nil, discipline: nil, wishlist: nil)
          @bus = bus
          @committer = committer
          @conflict_resolver = conflict_resolver
          @llm_router = llm_router
          @root = root
          @resource_budget = ResourceBudget.new(root:)
          @agent = agent
          @scan_phase = ScanPhase.new(scanner:, root:, bus:)
          @preflight = preflight || Preflight.new(root:, bus:)
          @learnings = learnings
          @preamble = preamble
          @law_order = LawOrder.new(laws:, learnings:, bus:, root:)
          take_limits(clean_runs_required:, plateau_window:, ground_truth:, homeostat:, council:, visual_pass:, opportunity_pass:, discipline:, wishlist:)
        end

        # What a pass is judged by, apart from the collaborators it runs through:
        # when it may stop, when it has stopped moving, and who else gets a say.
        def take_limits(clean_runs_required:, plateau_window:, ground_truth:, homeostat:, council:, visual_pass:, opportunity_pass:, discipline:, wishlist:)
          @clean_runs_required = clean_runs_required
          @plateau_window = plateau_window
          @law_violation_counts = Hash.new(0)
          @law_recurrence = Hash.new(0)
          @ground_truth = ground_truth
          @homeostat = homeostat
          @council = council
          @visual_pass = visual_pass
          @opportunity_pass = opportunity_pass
          @wishlist = wishlist || Wishlist.new(root: @root, agent: @agent, event_bus: @bus)
          @discipline = discipline || ConvergenceDiscipline.new(root: @root, bus: @bus)
          @ground_truth_failures = 0
          emit_coverage = lambda do |target, pass|
            semantic = @scan_phase.semantic_full? ? "full" : "sampled clean-files"
            abstract = @council ? "bounded clean-streak review" : "unavailable"
            visual = @visual_pass&.applicable?(target) ? "rendered" : "not-applicable"
            opportunity = @opportunity_pass&.applicable?(target) ? "bounded" : "not-applicable"
            @bus&.publish(
              "fix_loop:coverage",
              pass:,
              lexical: "full",
              structural: "full",
              semantic:,
              abstract:,
              opportunity:,
              visual:,
            )
            Master::Trace::Dmesg.status(
              "fix0",
              "pass #{pass}, coverage lexical=full structural=full semantic=#{semantic} abstract=#{abstract} opportunity=#{opportunity} visual=#{visual}",
            )
          end
          @coverage_reporter = emit_coverage

          @pass_progress = false
        end

        def full_semantic!
          @scan_phase.full_semantic!
          self
        end

        def pass_progress? = @pass_progress == true

        # What this run could not inspect or run. A file whose scan fails, or a
        # stage that raises, costs that file or that stage and nothing else: the
        # pass carries on and every other stage still gets its turn. The run
        # then ends blocked instead of done, because a clean result over files
        # nobody read is not a clean result.
        def uninspected = (@uninspected ||= {})

        def stage_failures = (@stage_failures ||= Hash.new { |hash, stage| hash[stage] = [] })

        def gaps? = !(uninspected.empty? && stage_failures.empty?)

        def gaps = { uninspected: uninspected.dup, stage_failures: stage_failures.transform_values(&:dup) }

        def reset_gaps!
          @uninspected = nil
          @stage_failures = nil
          self
        end

        def violations(files) = resolve_violations(files.flat_map { |path| violations_for(path) })

        def violations_for(path)
          return [] unless File.exist?(path)

          preflight = @preflight.findings([path])
          return preflight.map { |finding| Violation.from_finding(finding, file: path.delete_prefix("#{@root}/")) } if preflight.any?

          result = @scan_phase.call(path)
          return skip_unreadable(path, result) unless result.ok?

          findings = result.value!.map { |finding| Master::Review::Scan::LawHealth.annotate(finding) }
          @bus&.publish("fix_loop:scan_progress", file: path.delete_prefix("#{ @root }/"), count: findings.size) if findings.any?
          findings.select { |finding| Severity.at_least?(finding.fetch(:severity, :warning), :warning) }
                  .map { |finding| Violation.from_finding(finding, file: path.delete_prefix("#{@root}/")) }
        end

        def resolve_violations(raw)
          @conflict_resolver.filter_findings(raw.map(&:to_h)).map { |row| row.transform_keys(&:to_sym) }
        end

        MAX_UNINSPECTED_LINES = 20

        # A file the scanner refuses or fails on is recorded and skipped, and the
        # pass goes on without it. The first few are named on the terminal; the
        # rest are counted in the terminal verdict.
        def skip_unreadable(path, result)
          relative = path.delete_prefix("#{@root}/")
          uninspected[relative] = result.message.to_s[0, 200]
          @bus&.publish("fix_loop:unreadable", file: relative, category: result.category, message: result.message)
          if uninspected.size <= MAX_UNINSPECTED_LINES
            Master::Trace::Dmesg.status("fix0", "scan skipped #{relative}: #{result.message}"[0, 180])
          end
          []
        end

        # A stage that raises costs that stage, not the pass. The error is kept
        # where the final verdict reads it, published, and printed once; the
        # caller continues with the fallback it named.
        def guarded(stage, pass, fallback = nil)
          yield
        rescue StandardError => e
          stage_failures[stage] << "pass #{pass}: #{e.class}: #{e.message.to_s[0, 160]}"
          @bus&.publish("fix_loop:stage_failed", stage:, pass:, error_class: e.class.name, message: e.message)
          Master::Trace::Dmesg.status("fix0", "pass #{pass}, #{stage} failed, carrying on: #{e.class}: #{e.message}"[0, 200])
          Master::Ground::Swallow.log(e, context: "fix_loop.stage.#{stage}", event_bus: @bus, severity: :load_bearing)
          fallback
        end

        def run_pass(files:, target:, pass:, deadline:, transaction_id:, history:, seen_snapshots:,
                     recurring_violations:, consecutive_clean:, wishlist_proposals: [], run_id: nil)
          pass_mtimes = mtimes(files)
          @pass_progress = false
          @coverage_reporter&.call(target, pass)
          start_pass_transaction(files:, target:, pass:, transaction_id:)
          found, streamed = observe_pass(files, target, pass, deadline)

          visual, opportunities, found = guarded(:evidence, pass, [nil, nil, found]) do
            merge_evidence_findings(target:, files:, pass:, found:)
          end
          found += Wishlist.findings(wishlist_proposals, root: @root)
          return evidence_abort_result(visual, opportunities) if found.empty? && (visual&.err? || opportunities&.err?)

          found, shed = guarded(:improvements, pass, [found, nil]) do
            supplement_with_improvements(found, pass:, files:, deadline:, consecutive_clean:)
          end
          return shed if shed

          # Convergence must score the complete observed surface: lexical,
          # structural, rendered, opportunity and wishlist evidence all belong
          # to the same pass before adaptive stopping decides whether to continue.
          @discipline.observe(pass:, findings: found, files:, progressed: @pass_progress)
          return clean_pass_result(files, pass_mtimes, pass, consecutive_clean) if found.empty?
          return plateau_result if stagnant?(history, seen_snapshots, recurring_violations, found, pass, progressed: @pass_progress)

          ## A reload skips the law stage: it would ask the model about the whole
          # scan on code that is already out of date.
          dispatch_llm_stages(unstreamed(found, streamed), files, pass, deadline, visual, run_id:) unless CodeWatch.requested?
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

        # found may now hold three kinds of finding -- ordinary law
        # violations, council-selected improvements, and rendered-visual
        # findings -- each routed to the stage that knows how to fix it. A
        # shed here (unlike supplement_with_improvements above) does not
        # abort: found is non-empty, so the transaction still delivers
        # whatever the fast/observation stages already produced.
        # Each stage below is guarded on its own: one that raises is recorded and
        # the next still runs, so a council that cannot meet does not take the
        # model fixes, the visual pass or the wishlist down with it.
        def dispatch_llm_stages(found, files, pass, deadline, visual, run_id: nil)
          resources = @resource_budget.measure
          if @resource_budget.critical?(resources)
            @bus&.publish("fix_loop:model_work_shed", pass:, reasons: resources[:reasons], values: resources[:values])
            Master::Trace::Dmesg.status("fix0", "pass #{pass}, model work shed: #{resources[:reasons].join("; ")}")
            return
          end

          @homeostat&.observe(:llm_call)
          routed = route_findings(found)
          source_found = routed.fetch(:source)
          council = guarded(:council, pass) { @council&.run(files: files_with_violations(source_found, files), pass:, deadline:) } if source_found.any?
          guarded(:model_fixes, pass) { run_llm_stage(source_found, files, pass, deadline, council:) } if source_found.any?
          guarded(:improvements_fix, pass) { run_improvement_stage(routed.fetch(:improvement), pass:, files:, deadline:) } if routed.fetch(:improvement).any?
          guarded(:opportunities, pass) { run_opportunity_stage(routed.fetch(:opportunity), files, pass, deadline, council:) } if routed.fetch(:opportunity).any?
          guarded(:visual, pass) do
            run_visual_stage(routed.fetch(:visual), pass:, image: visual&.value!&.fetch(:image, nil), files:, deadline:)
          end if routed.fetch(:visual).any?
          guarded(:wishlist, pass) { run_wishlist_stage(routed.fetch(:wishlist), pass:, files:, deadline:, run_id:) } if routed.fetch(:wishlist).any?
        end

        # Each kind of finding goes to the stage that knows how to fix it; what
        # no special stage claims is source the model repairs.
        def route_findings(found)
          by_law = ->(law_id) { found.select { |violation| violation[:law].to_s == law_id } }
          special = [VisualPass::LAW_ID, OpportunityPass::LAW_ID, CouncilRound::IMPROVEMENT_LAW_ID, Wishlist::LAW_ID]
          {
            source: unremembered(found.reject { |violation| special.include?(violation[:law].to_s) }),
            improvement: by_law.(CouncilRound::IMPROVEMENT_LAW_ID),
            opportunity: by_law.(OpportunityPass::LAW_ID),
            visual: by_law.(VisualPass::LAW_ID),
            wishlist: by_law.(Wishlist::LAW_ID),
          }
        end

        def run_fast_stage(files, pass)
          fixed = fast_pass(files)
          if fixed > 0
            @pass_progress = true
            @committer.commit_if_dirty("fix_loop: fast-fix [pass #{pass}]", owned_paths: files)
          end
          fixed
        end

        def observe_pass(files, target, pass, deadline)
          guarded(:fast_fixes, pass) { run_fast_stage(files, pass) }
          found, streamed = streaming_observation(files, target, pass, deadline)
          structure = files.empty? ? [] : guarded(:structure, pass, []) { structural_findings(files:) }
          [found + structure, streamed]
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
          @pass_progress = true if llm_fixed.positive?
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
          proof = @discipline.clean_proof(files:, pass:, clean_runs: clean_count, findings: ground_truth)
          unless proof[:eligible]
            return PassResult.new(
              status: proof[:fatal] ? :validation_failed : :continue,
              consecutive_clean: proof[:fatal] ? 0 : clean_count,
              message: proof[:reason],
            )
          end
          @bus&.publish("fix_loop:convergence_proof", pass:, clean_runs: clean_count,
                        files_verified: proof[:files_verified], quality_delta: proof[:quality_delta],
                        diminishing_returns: proof[:diminishing_returns], best_pass: proof[:best_pass])
          status = :clean
          PassResult.new(status:, message: "clean after #{pass} pass(es)", consecutive_clean: clean_count)
        end

        def ground_truth_violations(files)
          return [] unless @ground_truth

          files.filter_map do |path|
            next unless File.exist?(path)

            result = @ground_truth.assert_fresh!(path, reason: "claim_task_complete")
            next if result.ok?

            { law: "GROUND_TRUTH", file: path.delete_prefix("#{@root}/"), line: 0, message: result.message }
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
          tally = found.group_by { |v| v[:law].to_s }.transform_values(&:size)
          tally.each do |law_id, _|
            @law_recurrence[law_id] += 1
            next unless @law_recurrence[law_id] >= 3

            @law_recurrence.delete(law_id)
            sample = found.select { |v| v[:law].to_s == law_id }.first(5)
            @bus&.publish("fix_loop:soul_proposal", root: @root, law: law_id, sample:)
          end
          (@law_recurrence.keys - tally.keys).each { |key| @law_recurrence.delete(key) }
        end
        def circuit_open? = @llm_router.circuit_open?
        def open_breakers = @llm_router.open_breakers
      end
    end
  end
end