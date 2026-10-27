# frozen_string_literal: true

require "pathname"
require "set"
require_relative "../../four_stream_assessment"
require_relative "../../surface_evidence"

module Master
  module Fix
    class FixLoop
      class PassRunner
        # Runtime Law × stream × surface evidence and its source receipts.
        # This module owns measurement bookkeeping only; scanner, visual,
        # opportunity, run journal, and convergence implementations stay in
        # their existing owners.
        module AssessmentMatrix
          # Report concrete per-target adapter capability in the plan. Capability
          # inventory is not evidence of a successful measurement; missing assessors
          # still leave the completion ledger INCONCLUSIVE.
          def assessment_adapters(target:)
            visual_applicable = @visual_pass&.applicable?(target)
            visual = visual_applicable == true
            opportunities_applicable = @opportunity_pass&.applicable?(target)
            opportunities = opportunities_applicable == true
            {
              "whole_file" => @scan_phase ? "scanner" : "unavailable",
              "paths" => @scanner.respond_to?(:scan) ? "scanner" : "unavailable",
              "lines" => @scanner.respond_to?(:scan) ? "scanner" : "unavailable",
              "syntax_tree" => @scanner.respond_to?(:scan) ? "language_dispatch" : "unavailable",
              "structured_data" => @scanner.respond_to?(:scan) ? "scanner_path_filter" : "unavailable",
              "cross_file" => @reference_graph&.respond_to?(:build) ? "reference_graph" : "unavailable",
              "lexical_opportunities" => if @opportunity_pass.nil?
                                           "unavailable"
                                         elsif opportunities
                                           "opportunity_pass"
                                         else
                                           "not_applicable_to_target"
                                         end,
              "semantic_violations" => @scan_phase&.semantic_full? ? "full_semantic_mode" : "sampled_or_budgeted",
              "semantic_opportunities" => @council&.respond_to?(:improve) ? "bounded_council" : "unavailable",
              "rendered_ui" => if @visual_pass.nil?
                                 "unavailable"
                               elsif visual
                                 "visual_pass"
                               else
                                 "not_applicable_to_target"
                               end,
              "interactive_behavior" => if @visual_pass.nil?
                                          "unavailable"
                                        elsif visual
                                          "browser_journeys"
                                        else
                                          "not_applicable_to_target"
                                        end,
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

          # The matrix population is the canonical YAML Law catalogue projected
          # into executable definitions and Ruby detector adapters. Each Law ID
          # appears once; semantic and visual reviewers consume that same ID set.
          def begin_assessment_run(files:, plan:)
            @assessment_plan = plan
            @assessment_surface_cache = {}
            @assessment_surface_report = nil
            @assessment_surface_receipts = {}
            @assessment_ledger = nil
            @assessment_observation = nil
            @assessment_law_info = nil
            @assessment_unclassified = []
            @assessment_last_pass = 0

            require File.join(Master::ROOT, "law", "definition") unless defined?(::Law::Definition)
            ::Law.load_all(File.join(Master::ROOT, "law")) if ::Law.definitions.empty?
            require File.join(Master::ROOT, "lib", "review", "scan", "law_registry_audit") unless
              defined?(Master::Review::Scan::LawRegistryAudit)
            Master::Review::Scan::LawRegistryAudit.new(root: Master::ROOT).call.assert_reconciled!

            info = {}
            Array(::Law.definitions.values).each do |law|
              next if law.respond_to?(:enforceable?) && !law.enforceable?

              id = assessment_law_id(law)
              next if id.empty?

              # Every Law is assessed in every stream. An adapter may return
              # NOT_APPLICABLE only with evidence; a missing assessor stays
              # INCONCLUSIVE and cannot turn into a clean result.
              streams = FourStreamAssessment::STREAMS
              declared_surfaces = law.respond_to?(:assessment_surfaces) ? law.assessment_surfaces : []
              info[id] = {
                id:,
                source_kind: :canonical,
                law:,
                scanner_law: nil,
                yaml_entry: nil,
                streams: streams.uniq.freeze,
                surfaces: Array(declared_surfaces).map(&:to_sym).uniq.freeze,
                unmeasurable_reason: nil,
                unmeasurable_streams: begin
                  lexical = %i[lexical_violations lexical_opportunities]
                  if !law.scannable?
                    lexical
                  elsif law.mode.to_sym == :violation
                    [:lexical_opportunities]
                  elsif law.mode.to_sym == :opportunity
                    [:lexical_violations]
                  else
                    lexical
                  end
                end.freeze,
              }
            end

            scanner_laws = @scanner.respond_to?(:laws) ? Array(@scanner.laws) : []
            scanner_laws.each do |law|
              id = assessment_law_id(law)
              next if id.empty?
              next if assessment_existing_law_id(info, id)

              class_name = law.class.name.to_s
              semantic = class_name.match?(/AdversarialLaw|CommentDriftLaw|SemanticLaw/) ||
                (law.respond_to?(:set_agent) && !law.respond_to?(:check_ast))
              mode = law.respond_to?(:mode) ? law.mode.to_s : ""
              streams = FourStreamAssessment::STREAMS
              surfaces = ::Law::ASSESSMENT_SURFACES
              unmeasurable_streams = if semantic || mode == "semantic"
                %i[lexical_violations lexical_opportunities]
              elsif mode == "opportunity"
                [:lexical_violations]
              else
                [:lexical_opportunities]
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
                unmeasurable_streams: unmeasurable_streams.freeze,
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
                # The aggregate opportunity engine has no per-surface clean receipt.
                # Keep one source-level cell and leave its negative result inconclusive.
                surfaces: [:whole_file].freeze,
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
                surfaces: %i[rendered_ui interactive_behavior].freeze,
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
            @assessment_surface_presence = nil
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
              @assessment_surface_presence = nil
              @assessment_surface_report = nil
              @assessment_surface_receipts = {}
              @assessment_surface_cache = {}
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

          def assessment_plan_refreshed!(plan)
            @assessment_mutex&.synchronize do
              @assessment_plan = plan
              @assessment_surface_presence = nil
              @assessment_surface_report = nil
              @assessment_surface_receipts = {}
              @assessment_surface_cache = {}
              @assessment_scope = plan.sources.map { |source| File.expand_path(source.path, plan.root) }.sort.freeze
            end
            self
          rescue StandardError => e
            stage_failures[:assessment_matrix] << "plan metadata refresh: #{e.class}: #{e.message.to_s[0, 150]}"
            self
          end

          def assessment_matrix_status
            return :not_measured unless @assessment_ledger

            @assessment_ledger.clean? && @assessment_surface_report&.fetch("complete", false) == true ? :complete : :incomplete
          rescue StandardError => e
            stage_failures[:assessment_matrix] << "status read: #{e.class}: #{e.message.to_s[0, 150]}"
            :incomplete
          end

          def assessment_matrix_summary
            return { status: "not_measured", reason: "no scanner-backed Law population was available" } unless @assessment_ledger

            @assessment_ledger.summary.merge(
              status: assessment_matrix_status.to_s,
              surface_coverage_complete: @assessment_surface_report&.fetch("complete", false) == true,
              surface_coverage_digest: @assessment_surface_report&.fetch("digest", nil),
              surface_coverage: surface_coverage_summary,
            )
          rescue StandardError => e
            { status: "incomplete", reason: "matrix summary failed: #{e.class}: #{e.message.to_s[0, 150]}" }
          end

          def assessment_matrix_evidence
            {
              status: assessment_matrix_status.to_s,
              plan_digest: @assessment_plan&.digest,
              source_digest: @assessment_plan&.source_digest,
              **assessment_matrix_summary,
              surface_coverage: surface_coverage_summary,
            }
          rescue StandardError => e
            { status: "incomplete", reason: "matrix evidence failed: #{e.class}: #{e.message.to_s[0, 150]}" }
          end

          # Full report passed to RunJournal for durable, checksum-addressed storage.
          # It is deliberately not embedded in the bounded terminal history.
          def assessment_matrix_artifact
            unless @assessment_ledger
              return {
                schema_version: 3,
                status: "not_measured",
                reason: "no scanner-backed Law population was available",
                target: @assessment_plan&.target,
                plan_digest: @assessment_plan&.digest,
                source_digest: @assessment_plan&.source_digest,
                law_digest: @assessment_plan&.law_digest,
                identity_digest: @assessment_plan&.identity_digest,
                scope_digest: @assessment_plan&.scope_digest,
                law_source_digest: @assessment_plan&.law_source_digest,
                authority_digest: @assessment_plan&.authority_digest,
                toolchain_digest: @assessment_plan&.toolchain_digest,
                exclusion_digest: @assessment_plan&.exclusion_digest,
                adapter_digest: @assessment_plan&.adapter_digest,
              }
            end

            @assessment_mutex.synchronize do
              {
                schema_version: 3,
                status: (assessment_matrix_status == :complete ? "complete" : "incomplete"),
                target: @assessment_plan&.target,
                plan_digest: @assessment_plan&.digest,
                source_digest: @assessment_plan&.source_digest,
                law_digest: @assessment_plan&.law_digest,
                identity_digest: @assessment_plan&.identity_digest,
                scope_digest: @assessment_plan&.scope_digest,
                law_source_digest: @assessment_plan&.law_source_digest,
                authority_digest: @assessment_plan&.authority_digest,
                toolchain_digest: @assessment_plan&.toolchain_digest,
                exclusion_digest: @assessment_plan&.exclusion_digest,
                adapter_digest: @assessment_plan&.adapter_digest,
                surface_coverage: @assessment_surface_report,
                ledger: @assessment_ledger.evidence_report,
              }
            end
          rescue StandardError => e
            {
              schema_version: 3,
              status: "incomplete",
              reason: "matrix artifact failed: #{e.class}: #{e.message.to_s[0, 150]}",
            }
          end
          
          private

          def surface_coverage_summary
            report = @assessment_surface_report
            return { status: "not_measured", reason: "surface adapters have not run" } unless report.is_a?(Hash)

            surfaces = report["surfaces"].is_a?(Hash) ? report["surfaces"] : {}
            {
              status: report["complete"] == true ? "complete" : "incomplete",
              digest: report["digest"],
              measured: surfaces.count { |_name, row| %w[assessed_clean not_applicable].include?(row["status"].to_s) },
              expected: surfaces.size,
              blockers: surfaces.filter_map do |name, row|
                next if %w[assessed_clean not_applicable].include?(row["status"].to_s)

                { surface: name, status: row["status"], reason: row["reason"].to_s[0, 180] }
              end.first(8),
            }
          end

          def surface_probe_candidate_clean?(observation:, signatures_stable:, semantic_gaps:, pending:, visual:, opportunities:)
            return false unless signatures_stable
            return false unless observation[:unclassified_findings].empty?
            return false unless observation[:findings].values.all?(&:empty?)
            return false unless semantic_gaps.empty? && pending.empty?
            return false unless @scan_phase&.semantic_full?

            visual_applicable = @visual_pass&.applicable?(@assessment_plan.target) == true
            opportunity_applicable = @opportunity_pass&.applicable?(@assessment_plan.target) == true
            return false unless surface_stage_clean?(visual, applicable: visual_applicable)
            return false unless surface_stage_clean?(opportunities, applicable: opportunity_applicable)

            true
          rescue StandardError
            false
          end

          def surface_stage_clean?(result, applicable:)
            return true unless applicable
            return false unless result&.ok?

            value = result.value!
            value.is_a?(Hash) && Array(value[:findings] || value["findings"]).empty?
          rescue StandardError
            false
          end

          def begin_assessment_pass(pass, files)
            return unless @assessment_ledger

            paths = Array(files).map { |path| File.expand_path(path) }.uniq.sort
            signatures = paths.to_h { |path| [path, assessment_signature(path)] }
            planned = @assessment_plan.source_signatures.to_h do |relative, signature|
              [File.expand_path(relative, @assessment_plan.root), signature]
            end
            stale_plan_paths = paths.select { |path| planned[path] != signatures[path] }
            @assessment_mutex.synchronize do
              @assessment_observation = {
                pass: Integer(pass),
                files: paths,
                signatures:,
                stale_plan_paths: stale_plan_paths.freeze,
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

            candidate_clean = surface_probe_candidate_clean?(
              observation:, signatures_stable:, semantic_gaps:, pending:, visual:, opportunities:
            )
            @assessment_surface_report = SurfaceEvidence.capture(
              root: @assessment_plan.root,
              target: @assessment_plan.target,
              plan: @assessment_plan,
              files: observation[:files],
              visual_result: visual,
              reference_graph: @reference_graph,
              cache: (@assessment_surface_cache ||= {}),
              run_expensive: candidate_clean,
            )
            @assessment_surface_receipts = @assessment_surface_report.fetch("details", {})
            @bus&.publish(
              "fix_loop:surface_coverage",
              target: @assessment_plan.target,
              complete: @assessment_surface_report["complete"] == true,
              digest: @assessment_surface_report["digest"],
              surfaces: @assessment_surface_report.fetch("surfaces", {}).transform_values { |row| row["status"] },
            )

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

          def valid_rendered_ui_receipt?(receipt)
            return false unless receipt.is_a?(Hash)
            return false unless (receipt["status"] || receipt[:status]).to_s == "assessed_clean"

            receipt_evidence = receipt["evidence"] || receipt[:evidence]
            captures = receipt_evidence.is_a?(Hash) ?
              Array(receipt_evidence["surfaces"] || receipt_evidence[:surfaces]) : []
            return false if captures.empty?

            validator = SurfaceEvidence.allocate
            captures.all? { |capture| validator.send(:valid_rendered_capture?, capture) }
          rescue StandardError
            false
          end

          def assessment_cell_result(law_id:, info:, stream:, surface:, pass:, observation:,
                                     signatures_stable:, semantic_gaps:, pending:, evidence:,
                                     visual:, opportunities:)
            declared_surfaces = Array(info[:surfaces]).map(&:to_sym)
            return assessment_result(:not_applicable, reason: "Law does not declare the #{surface} surface") unless declared_surfaces.include?(surface)
            if info[:unmeasurable_reason]
              return assessment_result(:inconclusive, reason: info[:unmeasurable_reason], evidence:)
            end
            if Array(info[:unmeasurable_streams]).map(&:to_sym).include?(stream)
              return assessment_result(
                :inconclusive,
                reason: "Law #{law_id} has no deterministic assessor for #{stream}; it cannot be marked clean",
                evidence:
              )
            end
            unless info[:streams].include?(stream)
              return assessment_result(:inconclusive, reason: "Law has no #{stream} assessor")
            end

            if info[:source_kind] != :visual &&
               law_id.to_s.casecmp?(VisualPass::LAW_ID) &&
               stream == :semantic_violations && surface == :rendered_ui
              return assessment_result(:inconclusive, reason: "rendered visual review returned no result", evidence:) unless visual
              return assessment_result(:inconclusive, reason: visual.message.to_s, evidence:) if visual.err?

              rendered_receipt = (@assessment_surface_receipts || {})["rendered_ui"]
              unless valid_rendered_ui_receipt?(rendered_receipt)
                reason = rendered_receipt.is_a?(Hash) ? rendered_receipt["reason"].to_s : "rendered UI receipt is missing"
                reason = "rendered UI receipt is absent, incomplete or lacks valid screenshot/geometry evidence" if reason.empty?
                return assessment_result(:inconclusive, reason:, evidence:)
              end

              visual_value = visual.value!
              unless visual_value.is_a?(Hash) &&
                     (visual_value.key?(:findings) || visual_value.key?("findings"))
                return assessment_result(:inconclusive, reason: "rendered visual review did not return a law-findings collection", evidence:)
              end

              visual_rows = Array(visual_value[:findings] || visual_value["findings"]).select do |row|
                (row[:law] || row["law"]).to_s.casecmp?(law_id)
              end
              visual_evidence = Array(evidence) + [{
                "surface_probe" => "rendered_ui",
                "status" => "assessed_clean",
                "evidence_sha256" => rendered_receipt["evidence_sha256"],
                "counts" => rendered_receipt["counts"],
              }]
              return assessment_result(visual_rows.any? ? :violation_found : :assessed_clean,
                evidence: visual_evidence, findings: visual_rows)
            end

            surface_evidence = nil
            if SurfaceEvidence::SURFACES.include?(surface.to_s)
              surface_receipt = @assessment_surface_receipts[surface.to_s]
              unless surface_receipt.is_a?(Hash)
                return assessment_result(:inconclusive, reason: "target-level #{surface} surface receipt is missing", evidence:)
              end

              probe_status = (surface_receipt["status"] || surface_receipt[:status]).to_s
              probe_reason = (surface_receipt["reason"] || surface_receipt[:reason]).to_s
              surface_evidence = {
                "surface_probe" => surface.to_s,
                "status" => probe_status,
                "evidence_sha256" => surface_receipt["evidence_sha256"] || surface_receipt[:evidence_sha256],
                "counts" => surface_receipt["counts"] || surface_receipt[:counts],
                "plan_digest" => @assessment_plan&.digest,
                "source_digest" => @assessment_plan&.source_digest,
              }.compact
              base_evidence = Array(evidence) + [surface_evidence]
              case probe_status
              when "not_applicable"
                return assessment_result(:not_applicable, reason: probe_reason.empty? ? "target has no #{surface} surface" : probe_reason, evidence: base_evidence)
              when "inconclusive"
                return assessment_result(:inconclusive, reason: probe_reason.empty? ? "#{surface} probe was inconclusive" : probe_reason, evidence: base_evidence,
                  findings: Array(surface_receipt["findings"] || surface_receipt[:findings]))
              when "violation_found"
                findings = Array(surface_receipt["findings"] || surface_receipt[:findings])
                if info[:source_kind] == :visual
                  return assessment_result(:violation_found, reason: probe_reason, evidence: base_evidence, findings:)
                end
                return assessment_result(:inconclusive,
                  reason: "#{surface} probe found a target-level issue not attributed to Law #{law_id}: #{probe_reason}",
                  evidence: base_evidence, findings:)
              when "assessed_clean"
                # The target-level receipt proves this surface was measured. The
                # active Law's existing scanner/semantic assessor still supplies
                # law-specific findings over the planned source scope.
              else
                return assessment_result(:inconclusive, reason: "#{surface} probe returned unknown status #{probe_status.inspect}", evidence: base_evidence)
              end
            end

            case info[:source_kind]
            when :opportunity
              return assessment_result(:inconclusive, reason: "opportunity assessor returned no result", evidence:) unless opportunities
              return assessment_result(:inconclusive, reason: opportunities.message.to_s, evidence:) if opportunities.err?

              values = opportunities.value!
              rows = Array(values[:findings] || values["findings"]).select do |row|
                (row[:law] || row["law"]).to_s.casecmp?(law_id)
              end
              receipt = values[:assessment_evidence] || values["assessment_evidence"]
              receipt_value = lambda do |key|
                receipt.is_a?(Hash) ? (receipt[key.to_sym] || receipt[key.to_s]) : nil
              end
              receipt_reason = Array(receipt_value.call(:reasons)).map(&:to_s).reject(&:empty?).first
              receipt_bound = receipt_value.call(:status).to_s == "complete" &&
                @assessment_plan &&
                receipt_value.call(:plan_digest).to_s == @assessment_plan.digest.to_s &&
                receipt_value.call(:source_digest).to_s == @assessment_plan.source_digest.to_s &&
                receipt_value.call(:scope_digest).to_s == @assessment_plan.scope_digest.to_s &&
                receipt_value.call(:target).to_s == @assessment_plan.target.to_s &&
                receipt_value.call(:source_hashes_verified) == true &&
                receipt_value.call(:snapshot_sha256).to_s == receipt_value.call(:snapshot_after_sha256).to_s
              cell_evidence = Array(evidence) + (receipt.is_a?(Hash) ? [receipt] : [])
              unless receipt_bound
                reason = receipt_reason || "opportunity assessment receipt is missing, unstable or not bound to the current FixPlan"
                return assessment_result(:inconclusive, reason:, evidence: cell_evidence, findings: rows)
              end

              return assessment_result(:opportunity_found, evidence: cell_evidence, findings: rows) if rows.any?

              assessment_result(:assessed_clean, evidence: cell_evidence)
            when :visual
              return assessment_result(:inconclusive, reason: "source generation changed during visual assessment", evidence:) unless signatures_stable
              return assessment_result(:inconclusive, reason: "rendered review returned no result", evidence:) unless visual
              return assessment_result(:inconclusive, reason: visual.message.to_s, evidence:) if visual.err?
              if surface == :interactive_behavior
                return assessment_result(:assessed_clean, evidence: Array(evidence) + [surface_evidence].compact)
              end

              values = visual.value!
              rows = Array(values[:findings] || values["findings"]).select do |row|
                (row[:law] || row["law"]).to_s.casecmp?(law_id)
              end
              status = rows.any? ? :violation_found : :assessed_clean
              return assessment_result(status, evidence:, findings: rows)
            end

            scoped_files = observation[:files].select do |path|
              assessment_law_applies?(info, path, stream:) &&
                assessment_surface_applies?(info, surface, path, stream:)
            end
            return assessment_result(:not_applicable, reason: "no eligible file matches this Law/surface scope") if scoped_files.empty?
            unless assessment_surface_supported?(info, surface, stream:)
              return assessment_result(:inconclusive, reason: "#{surface} has no assessor for this Law/stream adapter", evidence:)
            end

            cell_evidence = Array(evidence) + [surface_evidence].compact
            if surface == :structured_data
              parsed = scoped_files.map { |path| parse_structured_surface(path) }
              failure = parsed.find { |row| row[:status] != :assessed_clean }
              if failure
                return assessment_result(:inconclusive, reason: failure[:reason], evidence: cell_evidence)
              end
              cell_evidence += parsed.flat_map { |row| row[:evidence] }
            elsif surface == :syntax_tree
              receipts = @scanner.respond_to?(:ast_assessments) ? @scanner.ast_assessments : {}
              source_hashes = @assessment_plan.source_hashes.to_h do |relative, sha|
                [File.expand_path(relative, @assessment_plan.root), sha]
              end
              missing = []
              receipt_evidence = []
              scoped_files.each do |path|
                receipt = receipts[File.expand_path(path)]
                expected = source_hashes[File.expand_path(path)]
                unless receipt && receipt["status"] == "assessed" &&
                       expected && receipt["sha256"] == expected
                  missing << path
                  next
                end
                receipt_evidence << "prism_ast=#{File.basename(path)} sha256=#{receipt["sha256"]}"
              end
              if missing.any?
                return assessment_result(
                  :inconclusive,
                  reason: "syntax tree receipt missing/stale for #{missing.first(4).map { |path| path.delete_prefix("#{@root}/") }.join(", ")}",
                  evidence: cell_evidence
                )
              end
              cell_evidence += receipt_evidence
            end

            found = Array(observation[:findings][[law_id, stream]]).select do |row|
              scoped_files.include?(row["file"])
            end
            assessment_result_for_scope(
              stream:, applicable: scoped_files, found:, observation:, signatures_stable:,
              semantic: %i[semantic_violations semantic_opportunities].include?(stream),
              semantic_gaps:, pending:, evidence: cell_evidence
            )
          end

          def assessment_surface_supported?(info, surface, stream:)
            return true if SurfaceEvidence::SURFACES.include?(surface.to_s)

            semantic = %i[semantic_violations semantic_opportunities].include?(stream)
            case info[:source_kind]
            when :canonical
              return true if %i[whole_file lines documentation structured_data].include?(surface)
              return semantic if surface == :sections

              false
            when :scanner
              return true if %i[whole_file documentation structured_data].include?(surface)
              return semantic || !info[:scanner_law]&.respond_to?(:check_ast) if surface == :lines
              return semantic if surface == :sections
              return surface == :syntax_tree && info[:scanner_law]&.respond_to?(:check_ast)
              false
            when :yaml_declarative
              %i[whole_file lines documentation structured_data].include?(surface)
            when :opportunity
              info[:surfaces].include?(surface)
            when :visual
              surface == :rendered_ui
            else
              false
            end
          end

          def assessment_law_applies?(info, path, stream:)
            semantic = %i[semantic_violations semantic_opportunities].include?(stream)
            case info[:source_kind]
            when :canonical
              law = info[:law]
              # SemanticLaw deliberately considers every active Law on every
              # artifact. Language/path restrictions belong to the deterministic
              # adapter and must not erase universal semantic evidence.
              semantic || law.applies?(path, Master.language_for(path)&.to_sym)
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

          def assessment_surface_applies?(info, surface, path, stream:)
            extension = File.extname(path).downcase
            language = Master.language_for(path).to_s
            semantic = %i[semantic_violations semantic_opportunities].include?(stream)
            case surface
            when :repository_tree, :directories
              File.directory?(@assessment_plan.target)
            when :file_names, :paths
              !@assessment_plan.sources.empty?
            when :whole_file
              true
            when :lines
              semantic || info[:source_kind] != :canonical || info[:law].scope.to_sym == :line
            when :sections
              semantic
            when :syntax_tree
              !language.empty? && !%w[markdown yaml json toml].include?(language)
            when :cross_file
              @assessment_plan.sources.size > 1
            when :structured_data
              %w[.yml .yaml .json .toml].include?(extension) || %w[yaml json toml].include?(language)
            when :documentation
              %w[.md .markdown .rst .txt].include?(extension) || language == "markdown"
            when :media_assets
              assessment_target_has_assets?(%w[.png .jpg .jpeg .webp .gif .svg .pdf .wav .mp3 .m4a .flac .mp4 .mov .webm])
            when :compiled_assets
              assessment_target_has_compiled_assets?
            when :rendered_ui, :interactive_behavior
              assessment_target_has_rendered_ui?
            when :tests
              assessment_target_has_tests?
            when :runtime
              runtime_extensions = %w[.rb .rake .sh .zsh .js .jsx .ts .tsx .html .erb .css .scss]
              @assessment_plan.sources.any? { |source| runtime_extensions.include?(File.extname(source.path).downcase) }
            when :deployment
              assessment_target_has_deployment_surface?
            else
              false
            end
          end

          def assessment_target_has_assets?(extensions)
            key = [:asset_extensions, extensions.sort]
            @assessment_surface_presence ||= {}
            return @assessment_surface_presence[key] if @assessment_surface_presence.key?(key)

            target = @assessment_plan.target
            return @assessment_surface_presence[key] = false unless File.directory?(target)

            @assessment_surface_presence[key] = extensions.any? do |extension|
              Dir.glob(File.join(target, "**", "*#{extension}")).any? do |path|
                File.file?(path) && !File.symlink?(path)
              end
            end
          rescue StandardError => e
            @bus&.publish("fix_loop:assessment_surface_inventory_failed", surface: key&.first, error: e.message)
            @assessment_surface_presence[key] = true
          end

          def assessment_target_has_compiled_assets?
            @assessment_surface_presence ||= {}
            return @assessment_surface_presence[:compiled_assets] if @assessment_surface_presence.key?(:compiled_assets)

            paths = @assessment_plan.sources.map(&:path)
            @assessment_surface_presence[:compiled_assets] = paths.any? do |path|
              path.match?(%r{(?:public/assets|app/assets/builds|vendor/assets)/}) ||
                File.basename(path).match?(/\A(?:manifest(?:-[a-f0-9]+)?\.json|.+\.min\.(?:css|js))\z/i)
            end || assessment_target_has_assets?(%w[.map])
          rescue StandardError
            @assessment_surface_presence[:compiled_assets] = true
          end

          def assessment_target_has_rendered_ui?
            @assessment_surface_presence ||= {}
            return @assessment_surface_presence[:rendered_ui] if @assessment_surface_presence.key?(:rendered_ui)

            target = @assessment_plan.target
            front_end = @assessment_plan.sources.any? do |source|
              source.path.match?(%r{(?:app/views|views|templates|frontend|src)/}) &&
                %w[.erb .html .htm .css .scss .js .jsx .ts .tsx].include?(File.extname(source.path).downcase)
            end
            # Inventory UI independently of adapter availability. If a
            # target contains a frontend but has no visual adapter, its UI
            # cells are INCONCLUSIVE, not falsely NOT_APPLICABLE.
            @assessment_surface_presence[:rendered_ui] = front_end
          rescue StandardError
            @assessment_surface_presence[:rendered_ui] = true
          end

          def assessment_target_has_tests?
            @assessment_surface_presence ||= {}
            return @assessment_surface_presence[:tests] if @assessment_surface_presence.key?(:tests)

            @assessment_surface_presence[:tests] = @assessment_plan.sources.any? do |source|
              source.path.match?(%r{(?:\A|/)(?:test|tests|spec)(?:/|\z)}) ||
                File.basename(source.path).match?(/(?:_test|_spec)\.(?:rb|js|ts|jsx|tsx)\z/)
            end
          end

          def assessment_target_has_deployment_surface?
            @assessment_surface_presence ||= {}
            return @assessment_surface_presence[:deployment] if @assessment_surface_presence.key?(:deployment)

            target = @assessment_plan.target
            target_label = target == @assessment_plan.root ? "." : target.delete_prefix(@assessment_plan.root + File::SEPARATOR)
            paths = @assessment_plan.sources.map(&:path)
            @assessment_surface_presence[:deployment] =
              target_label == "." || target_label.start_with?("OPENBSD", "RAILS") ||
              paths.any? do |path|
                File.basename(path).match?(/\A(?:Procfile|Dockerfile|compose\.ya?ml|.*\.service|.*deploy.*)\z/i) ||
                  path.match?(%r{(?:deploy|deployment|helm|terraform|k8s)/})
              end
          rescue StandardError
            @assessment_surface_presence[:deployment] = true
          end

          def parse_structured_surface(path)
            extension = File.extname(path).downcase
            text = File.read(path, encoding: "UTF-8")
            sha256 = Digest::SHA256.hexdigest(text)
            case extension
            when ".json"
              require "json"
              JSON.parse(text)
              parser = "JSON.parse"
            when ".yml", ".yaml"
              require "yaml"
              YAML.parse(text)
              parser = "YAML.parse"
            else
              return {
                status: :inconclusive,
                reason: "no structured-data parser registered for #{extension.empty? ? "extensionless input" : extension}",
                evidence: [],
              }
            end
            {
              status: :assessed_clean,
              evidence: ["structured_data=#{parser} sha256=#{sha256} path=#{path}"],
            }
          rescue StandardError => e
            {
              status: :inconclusive,
              reason: "structured-data parser failed for #{path}: #{e.class}: #{e.message.to_s[0, 160]}",
              evidence: [],
            }
          end

          def assessment_gap_paths(entries, applicable)
            keys = entries.respond_to?(:keys) ? entries.keys : Array(entries)
            scope = Array(applicable).map { |path| File.expand_path(path) }.to_set
            roots = [
              @assessment_plan&.root,
              (Master::REPO_ROOT if defined?(Master::REPO_ROOT)),
              Master::ROOT,
              @root,
            ].compact.map { |path| File.expand_path(path) }.uniq
            matched = Set.new
            unresolved = []

            keys.each do |key|
              raw = key.to_s
              candidates = if Pathname.new(raw).absolute?
                             [File.expand_path(raw)]
                           else
                             roots.map { |root| File.expand_path(raw, root) }
                           end
              path = candidates.find { |candidate| scope.include?(candidate) }
              if path
                matched << path
              elsif candidates.none? { |candidate| roots.any? { |root| candidate == root || candidate.start_with?(root + File::SEPARATOR) } }
                unresolved << raw
              end
            end

            [matched.to_a, unresolved]
          end

          def assessment_result_for_scope(stream:, applicable:, found:, observation:, signatures_stable:,
                                          semantic:, semantic_gaps:, pending:, evidence:)
            return assessment_result(:inconclusive, reason: "source bytes changed during this scan pass", evidence:) unless signatures_stable

            stale_plan = applicable.select { |path| Array(observation[:stale_plan_paths]).include?(path) }
            return assessment_result(
              :inconclusive,
              reason: "source differs from pinned FixPlan generation: #{stale_plan.first(4).map { |path| path.delete_prefix("#{@root}/") }.join(", ")}",
              evidence:
            ) if stale_plan.any?

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

            if found.any?
              status = %i[lexical_opportunities semantic_opportunities].include?(stream) ? :opportunity_found : :violation_found
              return assessment_result(status, evidence:, findings: found)
            end

            if semantic
              return assessment_result(:inconclusive, reason: "semantic coverage is sampled or budgeted", evidence:) unless @scan_phase.semantic_full?

              pending_paths, pending_unknown = assessment_gap_paths(pending, applicable)
              return assessment_result(
                :inconclusive,
                reason: "semantic reads pending for #{pending_paths.first(4).map { |path| path.delete_prefix("#{@root}/") }.join(", ")}",
                evidence:
              ) if pending_paths.any?
              return assessment_result(
                :inconclusive, reason: "semantic gap paths could not be scoped: #{pending_unknown.first(4).join(", ")}", evidence:
              ) if pending_unknown.any?

              gap_paths, gap_unknown = assessment_gap_paths(semantic_gaps, applicable)
              return assessment_result(
                :inconclusive,
                reason: "semantic read inconclusive for #{gap_paths.first(4).map { |path| path.delete_prefix("#{@root}/") }.join(", ")}",
                evidence:
              ) if gap_paths.any?
              return assessment_result(
                :inconclusive, reason: "semantic gap paths could not be scoped: #{gap_unknown.first(4).join(", ")}", evidence:
              ) if gap_unknown.any?
            end

            assessment_result(:assessed_clean, evidence:)
          end

          def assessment_result(status, reason: nil, evidence: [], findings: [])
            { status:, reason:, evidence: Array(evidence), findings: Array(findings) }
          end

          def record_assessment(law_id, stream, surface, pass, result)
            @assessment_mutex.synchronize do
              @assessment_ledger.record(
                law: law_id, stream:, surface:, status: result.fetch(:status),
                iteration: Integer(pass), generation: @assessment_ledger.generation,
                reason: result[:reason], evidence: result[:evidence], findings: result[:findings]
              )
            end
          end
        end
      end
    end
  end
end
