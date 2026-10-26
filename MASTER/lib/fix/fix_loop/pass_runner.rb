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
require_relative "../four_stream_assessment"
require_relative "../scan_skip_guard"
require_relative "../transaction"
require_relative "../resource_budget"
require_relative "../wishlist"
require_relative "../constitutional_check"
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
                       visual_pass: nil, opportunity_pass: nil, preflight: nil, discipline:, wishlist:,
                       reference_graph: nil)
          @bus = bus
          @committer = committer
          @conflict_resolver = conflict_resolver
          @llm_router = llm_router
          @root = root
          @reference_graph = reference_graph
          @resource_budget = ResourceBudget.new(root:)
          @agent = agent
          @scanner = scanner
          @assessment_mutex = Mutex.new
          @assessment_ledger = nil
          @assessment_observation = nil
          @assessment_plan = nil
          @assessment_last_pass = 0
          @scan_phase = ScanPhase.new(scanner:, root:, bus:)
          @skip_guard = ScanSkipGuard.new
          @preflight = preflight || Preflight.new(root:, bus:)
          @learnings = learnings
          @preamble = preamble
          @base_preamble = preamble
          @law_order = LawOrder.new(laws:, learnings:, bus:, root:)
          take_limits(clean_runs_required:, plateau_window:, ground_truth:, homeostat:, council:, visual_pass:, opportunity_pass:, discipline:, wishlist:)
        end

        def take_limits(clean_runs_required:, plateau_window:, ground_truth:, homeostat:, council:, visual_pass:, opportunity_pass:, discipline:, wishlist:)
          @clean_runs_required = clean_runs_required
          @plateau_window = plateau_window
          @violation_counts = Hash.new(0)
          @law_recurrence = Hash.new(0)
          @ground_truth = ground_truth
          @homeostat = homeostat
          @council = council
          @visual_pass = visual_pass
          @opportunity_pass = opportunity_pass
          @wishlist = wishlist
          @discipline = discipline
          @ground_truth_failures = 0
          emit_coverage = lambda do |target, pass|
            semantic = @scan_phase.semantic_full? ? "full" : "conditional/sampled"
            abstract = @council ? "bounded clean-streak review" : "unavailable"
            visual = @visual_pass&.applicable?(target) ? "rendered" : "not-applicable"
            lexical_opportunities = @opportunity_pass&.applicable?(target) ? "bounded-tree-heuristics" : "no-universal-adapter"
            matrix_status = assessment_matrix_status
            matrix_label = case matrix_status
                           when :complete then "runtime_ledger_complete"
                           when :incomplete then "runtime_ledger_partial"
                           else "contract_only_not_measurement"
                           end
            matrix_summary = assessment_matrix_summary
            @bus&.publish(
              "fix_loop:coverage",
              pass:,
              lexical: "mechanical+structural-full-eligible-corpus",
              structural: "full-eligible-corpus",
              lexical_violations: "fixture-backed deterministic detectors; universal tree coverage not measured",
              lexical_opportunities: "declared opportunity-mode detectors plus bounded tree heuristics; universal per-law coverage not measured",
              semantic_violations: semantic == "full" ? "separate violation request per applicable recognized-language file; surface matrix not measured" : semantic,
              semantic_opportunities: semantic == "full" ? "separate opportunity request per applicable recognized-language file; surface matrix not measured" : semantic,
              semantic:,
              abstract:,
              opportunity: lexical_opportunities,
              visual:,
              assessment_matrix: matrix_label,
              assessment_matrix_status: matrix_status.to_s,
              assessment_matrix_summary: matrix_summary,
            )
            Master::Trace::Dmesg.status(
              "fix0",
              "pass #{pass}, coverage lexical-violations=mechanical+structural lexical-opportunities=#{lexical_opportunities} semantic-violations=#{semantic} semantic-opportunities=#{semantic} visual=#{visual} law-stream-surface-matrix=#{matrix_status.to_s.upcase}",
            )
          end
          @coverage_reporter = emit_coverage
          @pass_progress = false
        end

        def full_semantic!
          @scan_phase.full_semantic!
          self
        end

        def research_brief=(brief)
          detail = brief.to_s.strip
          @preamble = detail.empty? ? @base_preamble : [@base_preamble.to_s.strip, detail].join("\n\n")
        end

        def pass_progress? = @pass_progress == true
        def publish_pending! = @committer.publish_pending!

        def uninspected = (@uninspected ||= {})
        def stage_failures = (@stage_failures ||= Hash.new { |hash, stage| hash[stage] = [] })
        def semantic_inconclusive
          @scanner.respond_to?(:semantic_gaps) ? @scanner.semantic_gaps : {}
        end

        # Report concrete per-target adapter capability in the plan. Capability
        # inventory is not evidence of a successful measurement; missing assessors
        # still leave the completion ledger INCONCLUSIVE.
        def assessment_adapters(target:)
          visual = @visual_pass&.applicable?(target) == true
          opportunities = @opportunity_pass&.applicable?(target) == true
          {
            "whole_file" => @scan_phase ? "scanner" : "unavailable",
            "paths" => @scanner.respond_to?(:scan) ? "scanner" : "unavailable",
            "lines" => @scanner.respond_to?(:scan) ? "scanner" : "unavailable",
            "syntax_tree" => @scanner.respond_to?(:scan) ? "language_dispatch" : "unavailable",
            "structured_data" => @scanner.respond_to?(:scan) ? "scanner_path_filter" : "unavailable",
            "cross_file" => @reference_graph&.respond_to?(:build) ? "reference_graph" : "unavailable",
            "lexical_opportunities" => opportunities ? "opportunity_pass" : "not_applicable_to_target",
            "semantic_violations" => @scan_phase&.semantic_full? ? "full_semantic_mode" : "sampled_or_budgeted",
            "semantic_opportunities" => @council&.respond_to?(:improve) ? "bounded_council" : "unavailable",
            "rendered_ui" => visual ? "visual_pass" : "not_applicable_to_target",
            "interactive_behavior" => visual ? "browser_journeys" : "not_applicable_to_target",
            "tests" => "target_specific_runner_only",
            "runtime" => "target_specific_probe_only",
            "deployment" => "external_validation_not_universal",
          }.freeze
        end

        def plan_refresh_failed!(error)
          stage_failures[:fix_plan] << "#{error.class}: #{error.message.to_s[0, 180]}"
          self
        end

        def plan_refresh_succeeded!
          stage_failures.delete(:fix_plan)
          self
        end

        # The matrix population is the canonical executable Law registry plus
        # scanner-only adapters that report their own identities. LawBridgeLaw
        # and SemanticLaw are transport adapters, never duplicate Law rows.
        def begin_assessment_run(files:, plan:)
          @assessment_ledger = nil
          @assessment_observation = nil
          @assessment_law_info = nil
          @assessment_unclassified = []
          @assessment_last_pass = 0

          require File.join(Master::ROOT, "law", "definition") unless defined?(::Law::Definition)
          ::Law.load_all(File.join(Master::ROOT, "law")) if ::Law.definitions.empty?

          info = {}
          Array(::Law.definitions.values).each do |law|
            next if law.respond_to?(:enforceable?) && !law.enforceable?

            id = assessment_law_id(law)
            next if id.empty?

            streams = []
            streams << :lexical_violations if law.respond_to?(:scannable?) && law.scannable? && law.mode.to_sym == :violation
            streams << :lexical_opportunities if law.respond_to?(:scannable?) && law.scannable? && law.mode.to_sym == :opportunity
            if law.respond_to?(:semantic?) && law.semantic?
              streams.concat(%i[semantic_violations semantic_opportunities])
            end
            declared_surfaces = law.respond_to?(:assessment_surfaces) ? law.assessment_surfaces : []
            info[id] = {
              id:,
              source_kind: :canonical,
              law:,
              scanner_law: nil,
              yaml_entry: nil,
              streams: streams.uniq.freeze,
              surfaces: Array(declared_surfaces).map(&:to_sym).uniq.freeze,
              unmeasurable_reason: streams.empty? ?
                "conduct-only Law has no independent four-stream source assessor" : nil,
            }
          end

          scanner_laws = @scanner.respond_to?(:laws) ? Array(@scanner.laws) : []
          wrapper_ids = %w[law_bridge semantic yaml_declarative]
          scanner_laws.each do |law|
            id = assessment_law_id(law)
            next if id.empty? || wrapper_ids.include?(id.downcase)
            next if assessment_existing_law_id(info, id)

            class_name = law.class.name.to_s
            semantic = class_name.match?(/AdversarialLaw|CommentDriftLaw|SemanticLaw/) ||
              (law.respond_to?(:set_agent) && !law.respond_to?(:check_ast))
            mode = law.respond_to?(:mode) ? law.mode.to_s : ""
            streams = if mode == "opportunity"
                        [:lexical_opportunities]
                      elsif semantic
                        [:semantic_violations]
                      else
                        [:lexical_violations]
                      end
            surfaces = if law.respond_to?(:assessment_surfaces)
                         Array(law.assessment_surfaces)
                       elsif law.respond_to?(:check_ast)
                         %i[whole_file lines syntax_tree]
                       elsif semantic
                         %i[whole_file sections]
                       else
                         %i[whole_file lines]
                       end
            info[id] = {
              id:,
              source_kind: :scanner,
              law: nil,
              scanner_law: law,
              yaml_entry: nil,
              streams: streams.freeze,
              surfaces: surfaces.map(&:to_sym).uniq.freeze,
              unmeasurable_reason: nil,
            }
          end

          yaml_adapter = scanner_laws.find { |law| law.id.to_s.downcase == "yaml_declarative" }
          Array(yaml_adapter&.instance_variable_get(:@entries)).each do |entry|
            id = entry[:id].to_s.downcase.strip
            next if id.empty? || assessment_existing_law_id(info, id)

            info[id] = {
              id:,
              source_kind: :yaml_declarative,
              law: nil,
              scanner_law: nil,
              yaml_entry: entry,
              streams: [:lexical_violations].freeze,
              surfaces: %i[whole_file lines].freeze,
              unmeasurable_reason: nil,
            }
          end

          opportunity_applicable = @opportunity_pass&.applicable?(plan.target) == true
          if opportunity_applicable && !assessment_existing_law_id(info, OpportunityPass::LAW_ID)
            info[OpportunityPass::LAW_ID] = {
              id: OpportunityPass::LAW_ID,
              source_kind: :opportunity,
              law: nil,
              scanner_law: nil,
              yaml_entry: nil,
              streams: [:lexical_opportunities].freeze,
              surfaces: %i[repository_tree directories file_names paths whole_file lines].freeze,
              unmeasurable_reason: nil,
            }
          end

          visual_applicable = @visual_pass&.applicable?(plan.target) == true
          if visual_applicable && !assessment_existing_law_id(info, VisualPass::LAW_ID)
            info[VisualPass::LAW_ID] = {
              id: VisualPass::LAW_ID,
              source_kind: :visual,
              law: nil,
              scanner_law: nil,
              yaml_entry: nil,
              streams: [:semantic_violations].freeze,
              surfaces: [:rendered_ui].freeze,
              unmeasurable_reason: nil,
            }
          end

          if info.empty?
            stage_failures[:assessment_matrix] << "no canonical or scanner-only Law identities; matrix not measured"
            return self
          end

          @assessment_law_info = info.freeze
          @assessment_ledger = FourStreamAssessment.new(
            laws: info.keys,
            clean_passes: [Integer(@clean_runs_required), 2].max,
            surfaces: FourStreamAssessment::SURFACES,
          )
          @assessment_plan = plan
          @assessment_scope = Array(files).map { |path| File.expand_path(path) }.uniq.sort.freeze
          @bus&.publish(
            "fix_loop:assessment_matrix_started",
            law_population: info.size,
            canonical_laws: info.values.count { |row| row[:source_kind] == :canonical },
            scanner_only_laws: info.values.count { |row| row[:source_kind] == :scanner },
            yaml_declarative_laws: info.values.count { |row| row[:source_kind] == :yaml_declarative },
            synthetic_opportunity: opportunity_applicable,
            synthetic_visual: visual_applicable,
            surfaces: FourStreamAssessment::SURFACES.size,
            expected_cells: info.size * FourStreamAssessment::STREAMS.size * FourStreamAssessment::SURFACES.size,
            plan_digest: plan.digest,
            status: "incomplete_until_every_applicable_cell_is_proved",
          )
          self
        rescue StandardError => e
          stage_failures[:assessment_matrix] << "#{e.class}: #{e.message.to_s[0, 180]}"
          @bus&.publish("fix_loop:assessment_matrix_init_failed", error_class: e.class.name, message: e.message)
          @assessment_ledger = nil
          self
        end

        def assessment_law_id(law)
          value = law.respond_to?(:id) ? law.id : law
          value.to_s.strip
        rescue StandardError
          ""
        end

        def assessment_existing_law_id(info, value)
          needle = value.to_s
          info.keys.find { |candidate| candidate.casecmp?(needle) }
        end

        def assessment_plan_changed!(plan)
          return unless @assessment_ledger

          @assessment_mutex.synchronize do
            @assessment_ledger.invalidate!(
              iteration: @assessment_last_pass,
              reason: "fix plan changed to #{plan.digest}",
            )
            @assessment_plan = plan
            @assessment_scope = plan.sources.map { |source| File.expand_path(source.path, plan.root) }.sort.freeze
          end
          @bus&.publish(
            "fix_loop:assessment_generation",
            generation: @assessment_ledger.generation,
            iteration: @assessment_last_pass,
            plan_digest: plan.digest,
            source_digest: plan.source_digest,
          )
          self
        rescue StandardError => e
          stage_failures[:assessment_matrix] << "generation invalidation: #{e.class}: #{e.message.to_s[0, 150]}"
          self
        end

        def assessment_matrix_status
          return :not_measured unless @assessment_ledger

          @assessment_ledger.clean? ? :complete : :incomplete
        rescue StandardError => e
          stage_failures[:assessment_matrix] << "status read: #{e.class}: #{e.message.to_s[0, 150]}"
          :incomplete
        end

        def assessment_matrix_summary
          return { status: "not_measured", reason: "no scanner-backed Law population was available" } unless @assessment_ledger

          @assessment_ledger.summary.merge(status: assessment_matrix_status.to_s)
        rescue StandardError => e
          { status: "incomplete", reason: "matrix summary failed: #{e.class}: #{e.message.to_s[0, 150]}" }
        end

        def assessment_matrix_evidence
          {
            status: assessment_matrix_status.to_s,
            plan_digest: @assessment_plan&.digest,
            source_digest: @assessment_plan&.source_digest,
            **assessment_matrix_summary,
          }
        rescue StandardError => e
          { status: "incomplete", reason: "matrix evidence failed: #{e.class}: #{e.message.to_s[0, 150]}" }
        end
        def gaps? = [uninspected, stage_failures, semantic_inconclusive, semantic_pending].any? { |gap| !gap.empty? }
        def gaps = {
          uninspected: uninspected.dup,
          stage_failures: stage_failures.transform_values(&:dup),
          semantic_inconclusive: semantic_inconclusive.dup,
          semantic_pending: semantic_pending.dup,
        }

        def reset_gaps!
          @uninspected = nil
          @semantic_pending = nil
          @skip_guard.reset!
          @stage_failures = nil
          @scanner.reset_semantic_gaps! if @scanner.respond_to?(:reset_semantic_gaps!)
          self
        end

        def cleanup_visual_runtime
          @visual_pass&.stop_runtime!
        end

        def violations(files)
          paths = Array(files)
          # Preview calls this outside observe_pass; seed the denominator here too
          # so the systemic-skip guard has accurate evidence in both paths.
          @scan_total = paths.size
          resolve_violations(paths.flat_map { |path| violations_for(path) })
        end

        def violations_for(path)
          unless File.exist?(path)
            note_assessment_path(path, :failed, reason: "file absent at observation")
            return []
          end

          preflight = @preflight.findings([path])
          if preflight.any?
            note_assessment_path(path, :preflight, reason: "preflight short-circuited scanner observation")
            return preflight.map { |finding| Violation.from_finding(finding, file: path.delete_prefix("#{@root}/")) }
          end

          result = @scan_phase.call(path)
          unless result.ok?
            note_assessment_path(path, :failed, reason: result.message)
            return skip_unreadable(path, result)
          end

          findings = result.value!.map { |finding| Master::Review::Scan::LawHealth.annotate(finding) }
          note_assessment_path(path, :scanned, findings:)
          @bus&.publish("fix_loop:scan_progress", file: path.delete_prefix("#{ @root }/"), count: findings.size) if findings.any?
          findings.select { |finding| Severity.at_least?(finding.fetch(:severity, :warning), :warning) }
                  .map { |finding| Violation.from_finding(finding, file: path.delete_prefix("#{@root}/")) }
        end

        def resolve_violations(raw)
          @conflict_resolver.filter_findings(raw.map(&:to_h)).map { |row| row.transform_keys(&:to_sym) }
        end

        MAX_UNINSPECTED_LINES = 20

        def skip_unreadable(path, result)
          relative = path.delete_prefix("#{@root}/")
          uninspected[relative] = result.message.to_s[0, 200]
          @skip_guard.record(relative, result)
          @skip_guard.check!(total: @scan_total.to_i)
          @bus&.publish("fix_loop:unreadable", file: relative, category: result.category, message: result.message)
          if uninspected.size <= MAX_UNINSPECTED_LINES
            Master::Trace::Dmesg.status("fix0", "scan skipped #{relative}: #{result.message}"[0, 180])
          end
          []
        end

        def guarded(stage, pass, fallback = nil)
          enter_phase(stage)
          yield
        rescue StandardError => e
          stage_failures[stage] << "pass #{pass}: #{e.class}: #{e.message.to_s[0, 160]}"
          @bus&.publish("fix_loop:stage_failed", stage:, pass:, error_class: e.class.name, message: e.message)
          Master::Trace::Dmesg.status("fix0", "pass #{pass}, #{stage} failed, carrying on: #{e.class}: #{e.message}"[0, 200])
          Master::Ground::Swallow.log(e, context: "fix_loop.stage.#{stage}", event_bus: @bus, severity: :load_bearing)
          fallback
        end

        def enter_phase(stage, pass = nil)
          Master::Review::LLMDispatcher::PassClock.reset_cancel!
          @bus&.publish("fix_loop:phase", stage:, pass:)
        end

        def run_pass(files:, target:, pass:, deadline:, transaction_id:, history:, seen_snapshots:,
                     recurring_violations:, consecutive_clean:, wishlist_proposals: [], run_id: nil)
          pass_mtimes = mtimes(files)
          @pass_progress = false
          @human_decision_required = false
          @coverage_reporter&.call(target, pass)
          start_pass_transaction(files:, target:, pass:, transaction_id:, run_id:)
          begin_assessment_pass(pass, files)
          found, streamed = observe_pass(files, target, pass, deadline)

          visual, opportunities, found = guarded(:evidence, pass, [nil, nil, found]) do
            merge_evidence_findings(target:, files:, pass:, found:)
          end
          finalize_assessment_pass(pass, visual:, opportunities:)
          found += Wishlist.findings(wishlist_proposals, root: @root)
          return evidence_abort_result(visual, opportunities) if found.empty? && (visual&.err? || opportunities&.err?)

          found, shed = guarded(:improvements, pass, [found, nil]) do
            supplement_with_improvements(found, pass:, files:, deadline:, consecutive_clean:)
          end
          return shed if shed

          @discipline.observe(pass:, findings: found, files:, progressed: @pass_progress)
          unless Master::Fix::ConstitutionalCheck.admit_clean?(found)
            residual = Master::Fix::ConstitutionalCheck.residual_errors(found)
            Master::Trace::Dmesg.status(
              "fix0",
              "pass #{pass}: #{residual.size} constitutional error(s) block clean/done",
            )
            found = residual if found.empty?
          end
          return clean_pass_result(files, pass_mtimes, pass, consecutive_clean) if found.empty?
          return blockers_cleared(files, pass) if CheckFocus.cleared?(found)
          return plateau_result if stagnant?(history, seen_snapshots, recurring_violations, found, pass, progressed: @pass_progress)

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

        def begin_assessment_pass(pass, files)
          return unless @assessment_ledger

          paths = Array(files).map { |path| File.expand_path(path) }.uniq.sort
          signatures = paths.to_h { |path| [path, assessment_signature(path)] }
          @assessment_mutex.synchronize do
            @assessment_observation = {
              pass: Integer(pass),
              files: paths,
              signatures:,
              scanned: Set.new,
              refused: {},
              findings: Hash.new { |hash, key| hash[key] = [] },
              unclassified_findings: [],
            }
          end
        end

        def assessment_signature(path)
          return unless File.file?(path) && !File.symlink?(path)

          stat = File.stat(path)
          [stat.dev, stat.ino, stat.size, stat.mtime.to_r, stat.ctime.to_r]
        rescue StandardError
          nil
        end

        def note_assessment_path(path, state, reason: nil, findings: [])
          absolute = File.expand_path(path)
          @assessment_mutex.synchronize do
            observation = @assessment_observation
            return unless observation && observation[:files].include?(absolute)

            case state
            when :scanned
              observation[:scanned] << absolute
              Array(findings).each do |finding|
                row = finding.respond_to?(:to_h) ? finding.to_h.transform_keys(&:to_sym) : {}
                raw_id = (row[:law] || row[:law_id] || row[:rule]).to_s.strip
                next if raw_id.empty?

                law_id = assessment_existing_law_id(@assessment_law_info || {}, raw_id)
                unless law_id
                  observation[:unclassified_findings] << {
                    "law" => raw_id, "file" => absolute,
                    "reason" => "finding identity is absent from the runtime assessment population",
                  }
                  next
                end

                info = @assessment_law_info.fetch(law_id)
                tags = Array(row[:tags]).map(&:to_s)
                stream_tag = tags.find { |tag| FourStreamAssessment::STREAMS.map(&:to_s).include?(tag) }
                stream = stream_tag&.to_sym
                if stream.nil? && tags.include?("opportunity") && info[:streams].include?(:semantic_opportunities)
                  stream = :semantic_opportunities
                elsif stream.nil? && tags.include?("violation") && info[:streams].include?(:semantic_violations)
                  stream = :semantic_violations
                elsif stream.nil? && info[:streams].one?
                  stream = info[:streams].first
                end
                unless stream && info[:streams].include?(stream)
                  observation[:unclassified_findings] << {
                    "law" => law_id, "file" => absolute,
                    "reason" => "finding stream could not be resolved from explicit tags",
                  }
                  next
                end

                observation[:findings][[law_id, stream]] << {
                  "file" => absolute,
                  "line" => row[:line].to_i,
                  "message" => row[:message].to_s[0, 180],
                }
              end
            when :preflight, :failed
              observation[:refused][absolute] = reason.to_s[0, 200]
            end
          end
        rescue StandardError => e
          @bus&.publish("fix_loop:assessment_path_error", file: path.to_s, error: e.message)
        end

        def finalize_assessment_pass(pass, visual:, opportunities:)
          observation = @assessment_mutex.synchronize do
            current = @assessment_observation
            @assessment_observation = nil
            current
          end
          return unless observation && @assessment_ledger

          signatures_stable = observation[:files].all? do |path|
            observation[:signatures][path] == assessment_signature(path)
          end
          semantic_gaps = @scanner.respond_to?(:semantic_gaps) ? @scanner.semantic_gaps : {}
          pending = semantic_pending
          plan_digest = @assessment_plan&.source_digest.to_s
          evidence = [
            "plan_source_sha256=#{plan_digest}",
            "scanner=Master::Fix::Scanner#scan",
            "pass=#{pass}",
            "eligible_files=#{observation[:files].size}",
          ].freeze
          unclassified = observation[:unclassified_findings]
          unless unclassified.empty?
            stage_failures[:assessment_matrix] << "#{unclassified.size} unclassified finding(s): #{unclassified.first(2).map { |row| "#{row["law"]}@#{row["file"]}" }.join(", ")}"
            @bus&.publish("fix_loop:assessment_unclassified_findings", pass:, findings: unclassified.first(20))
          end

          @assessment_law_info.each do |law_id, info|
            FourStreamAssessment::STREAMS.each do |stream|
              FourStreamAssessment::SURFACES.each do |surface|
                result = assessment_cell_result(
                  law_id:, info:, stream:, surface:, pass:, observation:,
                  signatures_stable:, semantic_gaps:, pending:, evidence:,
                  visual:, opportunities:
                )
                record_assessment(law_id, stream, surface, pass, result)
              end
            end
          end
          @assessment_last_pass = Integer(pass)
          @bus&.publish(
            "fix_loop:assessment_matrix_pass",
            **@assessment_ledger.summary.merge(pass:, plan_source_digest: plan_digest)
          )
        rescue StandardError => e
          stage_failures[:assessment_matrix] << "pass #{pass}: #{e.class}: #{e.message.to_s[0, 180]}"
          @bus&.publish(
            "fix_loop:assessment_matrix_pass_failed",
            pass:, error_class: e.class.name, message: e.message
          )
        end

        def assessment_cell_result(law_id:, info:, stream:, surface:, pass:, observation:,
                                   signatures_stable:, semantic_gaps:, pending:, evidence:,
                                   visual:, opportunities:)
          declared_surfaces = Array(info[:surfaces]).map(&:to_sym)
          if !info[:streams].include?(stream)
            return assessment_result(:not_applicable, reason: "Law has no #{stream} detector/assessor")
          end
          return assessment_result(:not_applicable, reason: "Law does not declare the #{surface} surface") unless declared_surfaces.include?(surface)

          if info[:unmeasurable_reason]
            return assessment_result(:inconclusive, reason: info[:unmeasurable_reason], evidence:)
          end

          return assessment_result(:inconclusive, reason: "#{surface} has no assessor for this Law adapter", evidence:) unless assessment_surface_supported?(info, surface)

          case info[:source_kind]
          when :opportunity
            return assessment_result(:inconclusive, reason: "opportunity assessor returned no result", evidence:) unless opportunities
            return assessment_result(:inconclusive, reason: opportunities.message.to_s, evidence:) if opportunities.err?

            values = opportunities.value!
            rows = Array(values[:findings] || values["findings"]).select do |row|
              (row[:law] || row["law"]).to_s.casecmp?(law_id)
            end
            status = rows.any? ? :opportunity_found : :assessed_clean
            return assessment_result(status, evidence:, findings: rows)
          when :visual
            return assessment_result(:inconclusive, reason: "rendered review returned no result", evidence:) unless visual
            return assessment_result(:inconclusive, reason: visual.message.to_s, evidence:) if visual.err?

            values = visual.value!
            rows = Array(values[:findings] || values["findings"]).select do |row|
              (row[:law] || row["law"]).to_s.casecmp?(law_id)
            end
            status = rows.any? ? :violation_found : :assessed_clean
            return assessment_result(status, evidence:, findings: rows)
          end

          scoped_files = observation[:files].select do |path|
            assessment_law_applies?(info, path) && assessment_surface_applies?(info, surface, path)
          end
          return assessment_result(:not_applicable, reason: "no eligible file matches this Law/surface scope") if scoped_files.empty?

          if %i[repository_tree directories file_names paths syntax_tree cross_file structured_data
                documentation media_assets compiled_assets rendered_ui interactive_behavior tests runtime deployment].include?(surface) &&
             !%i[structured_data documentation].include?(surface)
            return assessment_result(:inconclusive, reason: "surface-specific measurement adapter is not registered", evidence:)
          end

          found = Array(observation[:findings][[law_id, stream]]).select do |row|
            scoped_files.include?(row["file"])
          end
          assessment_result_for_scope(
            stream:, applicable: scoped_files, found:, observation:, signatures_stable:,
            semantic: %i[semantic_violations semantic_opportunities].include?(stream),
            semantic_gaps:, pending:, evidence:
          )
        end

        def assessment_surface_supported?(info, surface)
          case info[:source_kind]
          when :canonical
            %i[whole_file lines sections structured_data documentation].include?(surface)
          when :scanner
            return true if %i[whole_file lines sections].include?(surface)
            return surface == :syntax_tree if info[:scanner_law]&.respond_to?(:check_ast)
            false
          when :yaml_declarative
            %i[whole_file lines].include?(surface)
          when :opportunity
            info[:surfaces].include?(surface)
          when :visual
            surface == :rendered_ui
          else
            false
          end
        end

        def assessment_law_applies?(info, path)
          case info[:source_kind]
          when :canonical
            law = info[:law]
            law.applies?(path, Master.language_for(path)&.to_sym)
          when :scanner
            law = info[:scanner_law]
            return true unless law.respond_to?(:applies_to?)

            languages = law.respond_to?(:languages) ? law.languages : nil
            law.applies_to?(path, languages)
          when :yaml_declarative
            entry = info[:yaml_entry]
            relative = path.delete_prefix("#{@root}/")
            return false if entry[:path_match] && !relative.include?(entry[:path_match].to_s.delete("/"))

            languages = Array(entry[:languages]).map(&:to_s)
            languages.empty? || languages.include?(Master.language_for(path).to_s)
          else
            true
          end
        rescue StandardError
          false
        end

        def assessment_surface_applies?(info, surface, path)
          extension = File.extname(path).downcase
          language = Master.language_for(path).to_s
          case surface
          when :whole_file
            true
          when :lines
            info[:source_kind] == :canonical ? info[:law].scope.to_sym == :line : true
          when :sections
            info[:source_kind] == :canonical ?
              (info[:law].scope.to_sym == :file || info[:law].semantic?) : true
          when :structured_data
            %w[.yml .yaml .json .toml].include?(extension) || %w[yaml json toml].include?(language)
          when :documentation
            %w[.md .markdown .rst .txt].include?(extension) || language == "markdown"
          else
            false
          end
        end

        def assessment_result_for_scope(stream:, applicable:, found:, observation:, signatures_stable:,
                                        semantic:, semantic_gaps:, pending:, evidence:)
          return assessment_result(:inconclusive, reason: "source bytes changed during this scan pass", evidence:) unless signatures_stable

          unread = applicable.reject { |path| observation[:scanned].include?(path) }
          return assessment_result(
            :inconclusive,
            reason: "scanner did not examine every applicable file: #{unread.first(4).map { |path| path.delete_prefix("#{@root}/") }.join(", ")}",
            evidence:
          ) if unread.any?

          refused = applicable.select { |path| observation[:refused].key?(path) }
          return assessment_result(
            :inconclusive,
            reason: "scan short-circuited for #{refused.first(4).map { |path| path.delete_prefix("#{@root}/") }.join(", ")}",
            evidence:
          ) if refused.any?

          if semantic
            return assessment_result(:inconclusive, reason: "semantic coverage is sampled or budgeted", evidence:) unless @scan_phase.semantic_full?
            return assessment_result(:inconclusive, reason: "semantic reads pending for #{pending.keys.first(4).join(", ")}", evidence:) if pending.any?
            return assessment_result(:inconclusive, reason: "semantic read inconclusive for #{semantic_gaps.keys.first(4).join(", ")}", evidence:) if semantic_gaps.any?
          end

          if found.any?
            status = %i[lexical_opportunities semantic_opportunities].include?(stream) ? :opportunity_found : :violation_found
            return assessment_result(status, evidence:, findings: found)
          end

          assessment_result(:assessed_clean, evidence:)
        end

        def assessment_result(status, reason: nil, evidence: [], findings: [])
          { status:, reason:, evidence: Array(evidence), findings: Array(findings) }
        end

        def record_assessment(law_id, stream, surface, pass, result)
          @assessment_ledger.record(
            law: law_id, stream:, surface:, status: result.fetch(:status),
            iteration: Integer(pass), generation: @assessment_ledger.generation,
            reason: result[:reason], evidence: result[:evidence], findings: result[:findings]
          )
        end

        # A finding that needs a person was never applied, so it does not taint the pass's other
        # repairs: they are delivered, and the finding is reported for a person. Ending the run here
        # threw away every verified fix of the pass and stopped the run on any one such finding.
        def deliver_pass(found, files, pass)
          delivery = @committer.finish_transaction("fix_loop: pass #{pass}", findings: found, owned_paths: files)
          return PassResult.new(status: :delivery_failed, consecutive_clean: 0, message: delivery.message) if delivery.err?

          if @human_decision_required
            Master::Trace::Dmesg.status("fix0", "pass #{pass}: a finding needs a person and was left; " \
                                                  "the rest was delivered")
          end
          PassResult.new(status: :continue, consecutive_clean: 0)
        end

        def clean_pass_result(files, pass_mtimes, pass, consecutive_clean)
          result = handle_clean_pass(files, pass_mtimes, pass, consecutive_clean)
          return abort_transaction(result) if result.status == :validation_failed

          finish_transaction(files, pass, result)
        end

        def start_pass_transaction(files:, target:, pass:, transaction_id:, run_id: nil)
          boundary_scope = Master::Phoenix.scope_for(target, root: @root)
          @committer.baseline!(scope: boundary_scope)
          @bus&.publish("fix_loop:boundary_scope", target:, boundaries: boundary_scope)
          transaction = Transaction.new(root: @root, paths: files, id: transaction_id, bus: @bus)
          @committer.begin_transaction!(transaction)
          @bus&.publish("fix_loop:pass_start", pass:, target:, file_count: files.size, run_id:)
        end

        def blockers_cleared(files, pass)
          Master::Trace::Dmesg.status("fix0", "pass #{pass}: the files the red checks named are clean (--until-checks)")
          finish_transaction(files, pass, PassResult.new(status: :blockers_cleared, consecutive_clean: 0,
                                                         message: "blockers cleared"))
        end

        def plateau_result
          abort_transaction
          PassResult.new(status: :plateau, consecutive_clean: 0)
        end

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

          enter_phase(:council_improve, pass)
          [found + Array(@council&.improve(files:, pass:, deadline:)), nil]
        end

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
          @scan_total = files.size
          guarded(:fast_fixes, pass) { run_fast_stage(files, pass) }
          guarded(:lane_probe, pass) { probe_lanes_once }
          enter_phase(:stream, pass)
          found, streamed = streaming_observation(files, target, pass, deadline)
          structure = files.empty? ? [] : guarded(:structure, pass, []) { structural_findings(files:) }
          [found + structure, streamed]
        end

        def probe_lanes_once
          return if @lanes_probed

          @lanes_probed = true
          return unless LaneProbe.enabled? && ENV["MASTER_IN_PROOF"] != "1" && @agent.respond_to?(:ask_once)

          models = if @agent.respond_to?(:candidate_models)
                     Array(@agent.candidate_models(task_type: :code_generation))
                   else
                     []
                   end
          models = models.select { |model| Master::Io::LaneSelection.alive?(model) }
          if models.empty?
            models = Master::Io::LaneSelection.catalogue.select do |model|
              Master::Io::LaneSelection.alive?(model)
            end
          end
          LaneProbe.run(models:, ask: LaneProbe.ask_with(@agent))
        end

        def run_observation_stage(files, target)
          violations(files).tap { |v| emit_topology(v, target) }
        end

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
          proof = @discipline.clean_proof(
            files:, pass:, clean_runs: clean_count, required_runs: @clean_runs_required, findings: ground_truth
          )
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
