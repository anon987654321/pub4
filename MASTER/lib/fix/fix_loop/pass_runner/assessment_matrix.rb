# frozen_string_literal: true

require "pathname"
require "set"
require_relative "../../four_stream_assessment"

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
              # SemanticLaw derives its questions from every active executable Law,
              # using the Law's ask when present and its repair contract otherwise.
              # Therefore both semantic streams cover the canonical population even
              # when a Law also has a deterministic detector.
              streams.concat(%i[semantic_violations semantic_opportunities])
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
              @assessment_scope = plan.sources.map { |source| File.expand_path(source.path, plan.root) }.sort.freeze
            end
            self
          rescue StandardError => e
            stage_failures[:assessment_matrix] << "plan metadata refresh: #{e.class}: #{e.message.to_s[0, 150]}"
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
          
          private

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
            return assessment_result(:not_applicable, reason: "Law does not declare the #{surface} surface") unless declared_surfaces.include?(surface)
            if info[:unmeasurable_reason]
              return assessment_result(:inconclusive, reason: info[:unmeasurable_reason], evidence:)
            end
            unless info[:streams].include?(stream)
              return assessment_result(:not_applicable, reason: "Law has no #{stream} detector/assessor")
            end

            case info[:source_kind]
            when :opportunity
              return assessment_result(:inconclusive, reason: "opportunity assessor returned no result", evidence:) unless opportunities
              return assessment_result(:inconclusive, reason: opportunities.message.to_s, evidence:) if opportunities.err?

              values = opportunities.value!
              rows = Array(values[:findings] || values["findings"]).select do |row|
                (row[:law] || row["law"]).to_s.casecmp?(law_id)
              end
              return assessment_result(:opportunity_found, evidence:, findings: rows) if rows.any?

              # This adapter aggregates heuristics and does not publish a per-surface
              # clean receipt. Its absence of findings is not evidence of clean scope.
              return assessment_result(
                :inconclusive,
                reason: "opportunity assessor does not publish per-surface clean receipts",
                evidence:
              )
            when :visual
              return assessment_result(:inconclusive, reason: "source generation changed during visual assessment", evidence:) unless signatures_stable
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
              assessment_law_applies?(info, path, stream:) &&
                assessment_surface_applies?(info, surface, path, stream:)
            end
            return assessment_result(:not_applicable, reason: "no eligible file matches this Law/surface scope") if scoped_files.empty?
            unless assessment_surface_supported?(info, surface, stream:)
              return assessment_result(:inconclusive, reason: "#{surface} has no assessor for this Law/stream adapter", evidence:)
            end

            cell_evidence = Array(evidence)
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
