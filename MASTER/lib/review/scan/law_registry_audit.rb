# frozen_string_literal: true

require "set"

module Master
  module Review
    module Scan
      # Audits executable law population vs Ruby scanner registry.
      class LawRegistryAudit
        Report = Data.define(
          :yaml_laws, :registry_ids, :kernel_ids, :lexical_wired, :lexical_unwired,
          :semantic_only, :structural_unwired, :dep_graph_gaps, :mechanical, :source_drift,
          :catalogue_drift, :declared_catalogue_gaps, :declared_unmapped_entries, :trace_debt, :trace_ceiling
        ) do
          def reconciled?
            source_drift.values.all?(&:empty?) && catalogue_integrity_errors.empty?
          end

          # Declared coverage gaps remain visible debt; only unexpected catalogue
          # shape/reference errors and debt beyond the declared ceiling block.
          # The executable Law catalogue is separate from law_map's conceptual
          # trace map. Missing concept links remain visible debt; missing Law
          # identity, source, modality, or surface coverage is a hard integrity error.
          def catalogue_integrity_errors
            structural = %i[invalid_status malformed_entries empty_without_declared_gap gap_with_law_ids unmapped_with_law_ids]
            hard = catalogue_drift.select do |kind, _ids|
              (kind.to_s.start_with?("manifest_") && kind != :manifest_without_deterministic_detector) ||
                structural.include?(kind)
            end
            errors = hard.flat_map do |kind, ids|
              ids.map { |id| "catalogue_#{kind}: #{id}" }
            end
            return errors if trace_debt.size <= trace_ceiling

            errors + ["trace_debt: #{trace_debt.size} untraced detectors exceeds declared ceiling #{trace_ceiling}"]
          end

          def reconciliation_errors
            source_drift.flat_map { |kind, ids| ids.map { |id| "#{kind}: #{id}" } } +
              catalogue_integrity_errors
          end

          def assert_catalogue_integrity!
            return true if catalogue_integrity_errors.empty?

            raise "Law catalogue integrity failed: #{catalogue_integrity_errors.join('; ')}"
          end

          def assert_reconciled!
            return true if reconciled?

            raise "Law catalogue is not reconciled: #{reconciliation_errors.join('; ')}"
          end

          # A clean report is only meaningful when its population is explicit.
          #
          # Counted, never subtracted. A rule may be semantic-only, mechanical-only,
          # or layered and therefore belong to both populations. The audit reports
          # those populations independently so a semantic layer can never disappear
          # merely because its catalogue representation changed.
          def coverage_line = "#{mechanical.size} of #{yaml_laws} laws run without a model " \
                              "(see rake lint:law_reach for what the rest need)"

          # The share of declared law that something can run. self_test.rb fails
          # below 35 and laws.yml self_test names the threshold.
          #
          # The weighted average that stood here averaged registry coverage against
          # a term reading `(wired + unwired) * 100 / (wired + unwired)` — 100.0 for
          # every possible corpus — so the score floored at 55.0 and the check below
          # 35 could not fail whatever the tree did.
          def adherence_pct
            return 100.0 if yaml_laws.zero?

            # Deterministic detectors only. Every catalogue row also goes to the
            # semantic adapter, so counting semantic_only in here made the share
            # mechanical + its complement: 100 for any corpus, the floor this
            # replaced.
            (mechanical.size * 100.0 / yaml_laws).round(1)
          end
        end

        def initialize(root: Master::ROOT)
          @root = root
        end

        def population
          @population ||= load_yaml_laws
        end

        def call
          yaml_entries = population
          registry = build_registry_ids
          c = classify_yaml_entries(yaml_entries, registry)

          catalogue = catalogue_report(
            map: Master.law("law_map", root: @root),
            executable_ids: law_ids,
            registry_ids: registry,
          )
          manifest = law_catalogue_report(yaml_entries, registry:)
          catalogue_drift = catalogue.fetch(:drift).merge(manifest.fetch(:drift))
          Report.new(
            yaml_laws: c[:yaml_ids].size,
            registry_ids: registry,
            kernel_ids: c[:kernel],
            lexical_wired: c[:lexical_wired],
            lexical_unwired: c[:lexical_unwired],
            semantic_only: c[:semantic_only],
            structural_unwired: c[:structural_unwired],
            dep_graph_gaps: ungraphed_law_ids(registry),
            mechanical: mechanical(yaml_entries, registry:).map { |law| law["id"] },
            source_drift: source_drift(yaml_entries, registry),
            catalogue_drift:,
            declared_catalogue_gaps: catalogue.fetch(:declared_gaps),
            declared_unmapped_entries: catalogue.fetch(:declared_unmapped),
            trace_debt: catalogue.fetch(:trace_debt),
            trace_ceiling: catalogue.fetch(:trace_ceiling),
          )
        end

        # One statement of "something can run this rule", because three check
        # banners and lib/operator/law_reach.rb all print a count of it and three
        # separate spellings of the question gave two answers.
        #
        # `folded_into` names the law that reports for this one: the id survives
        # so principle_map can trace it, and the detector exists once, elsewhere.
        def source_drift(yaml_entries, registry)
          yaml_ids = yaml_entries.map { |rule| key_of(rule) }.to_set
          executable_ids = law_ids
          detector_ids = registry.map(&:to_s).map(&:downcase).to_set

          {
            yaml_only: (yaml_ids - executable_ids - detector_ids).to_a.sort.freeze,
            law_only: (executable_ids - yaml_ids).to_a.sort.freeze,
            registry_only: (detector_ids - yaml_ids - executable_ids).to_a.sort.freeze,
          }.freeze
        end

        # Cross-check law_map against canonical Laws and scanner detectors.
        # Explicit gap/unmapped rows remain visible debt, not structural drift.
        def catalogue_report(map:, executable_ids:, registry_ids:)
          entries = map.fetch("laws", {})
          executable = executable_ids.map { |id| id.to_s.downcase }.to_set
          registry = registry_ids.map { |id| id.to_s.downcase }.to_set
          mapped = entries.values.flat_map do |entry|
            entry.is_a?(Hash) ? Array(entry["law_ids"]) : []
          end.map { |id| id.to_s.downcase }.to_set
          enforceable = executable | registry
          empty_unclassified = []
          gap_with_ids = []
          unmapped_with_ids = []
          invalid_status = []
          malformed_entries = []

          entries.each do |name, entry|
            unless entry.is_a?(Hash)
              malformed_entries << name.to_s
              next
            end
            ids = Array(entry["law_ids"]).map { |id| id.to_s.strip }.reject(&:empty?)
            status = entry["status"].to_s
            empty_unclassified << name.to_s if ids.empty? && !%w[gap unmapped].include?(status)
            gap_with_ids << name.to_s if status == "gap" && ids.any?
            unmapped_with_ids << name.to_s if status == "unmapped" && ids.any?
            invalid_status << name.to_s unless %w[covered gap unmapped].include?(status)
          end

          {
            drift: {
              executable_not_mapped: (executable - mapped).to_a.sort.freeze,
              mapped_without_enforceable: (mapped - enforceable).to_a.sort.freeze,
              empty_without_declared_gap: empty_unclassified.sort.freeze,
              gap_with_law_ids: gap_with_ids.sort.freeze,
              unmapped_with_law_ids: unmapped_with_ids.sort.freeze,
              invalid_status: invalid_status.uniq.sort.freeze,
              malformed_entries: malformed_entries.sort.freeze,
            }.freeze,
            declared_gaps: entries.filter_map do |name, entry|
              name.to_s if entry.is_a?(Hash) && entry["status"].to_s == "gap" && Array(entry["law_ids"]).empty?
            end.sort.freeze,
            declared_unmapped: entries.filter_map do |name, entry|
              name.to_s if entry.is_a?(Hash) && entry["status"].to_s == "unmapped" && Array(entry["law_ids"]).empty?
            end.sort.freeze,
            trace_debt: (registry - mapped).to_a.sort.freeze,
            trace_ceiling: Integer(map.fetch("law_trace_ceiling", 0)),
          }.freeze
        end

        def mechanical(entries, registry: build_registry_ids)
          entries.select do |law|
            detector_present?(registry, law["id"]) || detector_present?(registry, law["folded_into"])
          end
        end

        def detector_present?(registry, id)
          key = id.to_s.downcase
          return false if key.empty?

          registry.include?(key) || !!law_detector?(key)
        end

        # `Law.inherited` registers every subclass in the process, and a test
        # that defines one is in the same process. Measured: law_deps.ungraphed
        # read 133 on its own and 135 under `rake test`, so a ratchet on it would
        # have been measuring the suite rather than the corpus.
        # TestScanRuleFalsePositives::RaisingRule is the shape.
        #
        # A class whose source cannot be located counts as shipped: over-
        # reporting a rule is safe, and silently dropping one is how a census
        # stops measuring.
        # Anchored at the start as well as after a slash: a file run as the main
        # script reports the path it was invoked with, so `ruby -Itest
        # test/test_x.rb` yields a relative `test/test_x.rb` that a leading-slash
        # pattern misses — and the exclusion then works everywhere except in the
        # one place the test for it runs.
        TEST_DEFINED = %r{(?:\A|/)(?:test|spec)/}

        def shipped?(klass)
          location = klass.name && Object.const_source_location(klass.name)&.first
          location.nil? || !location.match?(TEST_DEFINED)
        end

        def ungraphed_law_ids(registry = nil)
          registry ||= build_registry_ids
          registry = registry.map { |id| id.to_s.downcase }.to_set
          deps = Master.law("law_deps", root: @root)
          graphed = deps.keys.map { |k| k.to_s.downcase }.to_set
          registry.reject { |id| graphed.include?(id) }.sort
        end

        private

        def law_detector?(id)
          return false if id.to_s.empty?

          require File.join(@root, "law", "definition") unless defined?(::Law)
          ::Law.load_all(File.join(@root, "law")) if ::Law.definitions.empty?
          # Callers hand in the downcased key every population compares on; Law ids are upper case.
          law = ::Law.definitions[id.to_s.upcase.to_sym] || ::Law.definitions[id.to_sym]
          law&.scannable?
        end

        # Asked of the loaded registry, not of the source text: law/prose.rb
        # generates its four rules from data/laws.yml, so a grep for a literal
        # `Law.define(:ID)` reads none of them.
        def law_ids
          require File.join(@root, "law", "definition") unless defined?(::Law)
          ::Law.load_all(File.join(@root, "law")) if ::Law.definitions.empty?
          ::Law.definitions.keys.map { |id| id.to_s.downcase }.to_set
        rescue StandardError => e
          raise "law registry law census failed: #{e.class}: #{e.message}"
        end

        # The audit's YAML population comes from the authored catalogue,
        # never from the Ruby populations it is supposed to reconcile.
        def load_yaml_laws
          data = Master.load_laws(root: @root)
          catalogue = data.fetch("law_catalogue") do
            raise "data/laws.yml has no law_catalogue; refusing a synthetic Law population"
          end
          entries = catalogue.fetch("entries") do
            raise "data/laws.yml law_catalogue has no entries"
          end
          raise "data/laws.yml law_catalogue entries must be a non-empty mapping" unless entries.is_a?(Hash) && !entries.empty?

          entries.map do |id, entry|
            raise "law_catalogue entry #{id} must be a mapping" unless entry.is_a?(Hash)

            entry.merge("id" => id.to_s)
          end
        end

        def law_catalogue_report(entries, registry:)
          data = Master.law("law_catalogue", root: @root)
          required_modalities = Master::LawVocabulary::MODALITIES
          required_surfaces = ::Law::ASSESSMENT_SURFACES.map(&:to_s)
          modalities = Array(data["modalities"]).map(&:to_s)
          surfaces = Array(data["surfaces"]).map(&:to_s)
          missing_modalities = required_modalities - modalities
          missing_surfaces = required_surfaces - surfaces
          unexpected_surfaces = surfaces - required_surfaces
          entry_without_source = []
          missing_source_files = []
          duplicate_definitions = []
          non_universal = []
          entry_missing_modalities = []
          without_deterministic_detector = []

          repo_root = File.dirname(File.expand_path(@root))
          entries.each do |entry|
            id = entry.fetch("id").to_s
            definitions = Array(entry["definition_sources"]).map(&:to_s)
            sources = definitions
            entry_without_source << id if sources.empty?
            duplicate_definitions << id if definitions.uniq.size > 1
            non_universal << id unless entry["universal"] == true
            entry_modalities = Array(entry["modalities"]).map(&:to_s).to_set
            absent_modalities = required_modalities.reject { |modality| entry_modalities.include?(modality) }
            entry_missing_modalities << "#{id}:#{absent_modalities.join(',')}" unless absent_modalities.empty?

            without_deterministic_detector << id unless detector_present?(registry, id)

            sources.uniq.each do |source|
              full_path = File.expand_path(source, repo_root)
              next if full_path.start_with?(repo_root + File::SEPARATOR) && File.file?(full_path)

              missing_source_files << "#{id}:#{source}"
            end
          end

          {
            drift: {
              manifest_missing_modalities: missing_modalities.sort.freeze,
              manifest_missing_surfaces: missing_surfaces.sort.freeze,
              manifest_unexpected_surfaces: unexpected_surfaces.sort.freeze,
              manifest_entries_without_source: entry_without_source.sort.freeze,
              manifest_missing_source_files: missing_source_files.sort.freeze,
              manifest_duplicate_definitions: duplicate_definitions.sort.freeze,
              manifest_non_universal: non_universal.sort.freeze,
              manifest_entry_missing_modalities: entry_missing_modalities.sort.freeze,
              manifest_without_deterministic_detector: without_deterministic_detector.sort.freeze,
            }.freeze,
          }.freeze
        end

        # The Laws whose detector is a `check` or a class: the population the
        # scanner registry held before every Law became one ::Law.define (a
        # `detect` regex Law is reached through law_detector? instead). LawTree
        # loads all of law/, so the cold-Zeitwerk undercount (81
        # where a loaded registry said 115) has no second population to come from.
        def build_registry_ids
          Review::Scan::LawTree.definitions
            .select { |law| law.check || law.detector }
            .reject { |law| law.detector && !shipped?(law.detector) }
            .map { |law| law.id.to_s.downcase }
            .to_set
        end

        def classify_yaml_entries(yaml_entries, registry)
          lexical_wired, lexical_unwired = yaml_entries.partition { |law| detector_present?(registry, law["id"]) }
          # The semantic adapter evaluates every catalogue entry, using the
          # authored question or a generic question built from its repair contract.
          semantic_only = lexical_unwired
          {
            yaml_ids: yaml_entries.map { |law| key_of(law) },
            kernel: yaml_entries.select { |law| law["tier"] == "kernel" }.map { |law| key_of(law) },
            lexical_wired: ids_of(lexical_wired), lexical_unwired: ids_of(lexical_unwired),
            semantic_only: ids_of(semantic_only), structural_unwired: []
          }
        end

        # The registry is keyed by downcased id; the report keeps the id as declared.
        def key_of(law) = law["id"].to_s.downcase
        def ids_of(laws) = laws.map { |law| law["id"] }
      end
    end
  end
end
