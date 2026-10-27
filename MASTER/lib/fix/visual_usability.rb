# frozen_string_literal: true

module Master
  module Fix
    module VisualUsability
      CATALOGUE_SECTION = "law_catalogue"
      REQUIRED_MODALITIES = %w[lexical semantic visual].freeze
      SUMMARY_LIMIT = 112

      module_function

      # Law identity and membership come exclusively from laws.yml. Runtime
      # definitions and detector classes supply implementation descriptions only.
      def ids
        catalogue_entries.keys.map(&:to_s).sort.freeze
      end

      def context
        load_laws!
        entries = catalogue_entries
        rows = ids.map do |id|
          entry = entries.fetch(id)
          "#{id}: #{summary_for(id, entry)}"
        end
        [
          "CANONICAL UNIVERSAL LAW CATALOGUE — #{rows.length} Laws from MASTER/data/laws.yml##{CATALOGUE_SECTION}.",
          "Every listed Law must be considered for this rendered surface and its interactions. Do not filter by programming language, source file type, or whether it has a deterministic detector. Apply the same underlying invariant to implementation, prose, imagery, layout, states, and behavior. If the rendered evidence cannot establish a verdict, report INCONCLUSIVE instead of omitting the Law.",
          *rows,
        ].join("\n")
      end

      def load_laws!
        require File.expand_path("../../law/definition", __dir__)
        ::Law.load_all(File.expand_path("../../law", __dir__)) if ::Law.definitions.empty?
        require File.join(Master::ROOT, "lib", "review", "scan", "law_dsl") unless
          defined?(Master::Review::Scan::LawDSL)
        require File.join(Master::ROOT, "lib", "review", "scan", "law_factory") unless
          defined?(Master::Review::Scan::LawFactory)

        report = Master::Review::Scan::LawRegistryAudit.new(root: Master::ROOT).call
        report.assert_reconciled!
        missing_modalities = REQUIRED_MODALITIES - Array(catalogue["modalities"]).map(&:to_s)
        raise "Law catalogue missing modalities: #{missing_modalities.join(', ')}" unless missing_modalities.empty?
        missing = ids - report.yaml_entries_ids_if_available
        raise "visual Law catalogue failed runtime reconciliation: #{missing.join(', ')}" unless missing.empty?

        true
      end

      def summary_for(id, entry)
        law = executable_definitions[id] || detector_definitions[id]
        details = if law
                    [law.respond_to?(:ask) ? law.ask : nil,
                     law.respond_to?(:practice) ? law.practice : nil,
                     law.respond_to?(:fix) ? law.fix : nil,
                     law.respond_to?(:description) ? law.description : nil]
                  else
                    []
                  end
        summary = details.find { |value| !value.to_s.strip.empty? }.to_s
        if summary.empty?
          sources = Array(entry["definition_sources"]) + Array(entry["detector_sources"])
          summary = sources.map { |source| File.basename(source.to_s, ".rb") }.join(" / ")
        end
        summary = "Universal requirement; use the canonical Law definition and evidence." if summary.empty?
        normalized = summary.gsub(/\s+/, " ").strip
        normalized.length > SUMMARY_LIMIT ? "#{normalized[0, SUMMARY_LIMIT - 1]}…" : normalized
      end

      def catalogue
        @catalogue ||= Master.law(CATALOGUE_SECTION, root: Master::ROOT)
      end

      def catalogue_entries
        entries = catalogue.fetch("entries")
        raise "canonical Law catalogue entries must be a non-empty mapping" unless entries.is_a?(Hash) && !entries.empty?

        entries
      end

      def executable_definitions
        @executable_definitions ||= ::Law.definitions.values.to_h { |law| [law.id.to_s.upcase, law] }
      end

      def detector_definitions
        @detector_definitions ||= Master::Review::Scan::Law.registry.each_with_object({}) do |klass, result|
          location = klass.name && Object.const_source_location(klass.name)&.first
          next if location&.match?(%r{(?:\A|/)(?:test|spec)/})

          law = Master::Review::Scan::LawFactory.build(klass, root: Master::ROOT)
          id = law.id.to_s.upcase
          result[id] ||= law unless id.empty?
        end
      end
    end
  end
end
