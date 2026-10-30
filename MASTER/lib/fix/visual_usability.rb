# frozen_string_literal: true

require_relative "../law_vocabulary"

module Master
  module Fix
    module VisualUsability
      CATALOGUE_SECTION = "law_catalogue"
      REQUIRED_MODALITIES = Master::LawVocabulary::MODALITIES
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
        Master::Review::Scan::LawTree.load!

        report = Master::Review::Scan::LawRegistryAudit.new(root: Master::ROOT).call
        report.assert_reconciled!
        missing_modalities = REQUIRED_MODALITIES - Array(catalogue["modalities"]).map(&:to_s)
        raise "Law catalogue missing modalities: #{missing_modalities.join(', ')}" unless missing_modalities.empty?
        raise "visual Law catalogue/runtime count drift: #{ids.length} catalogue entries, #{report.yaml_laws} audited" unless
          ids.length == report.yaml_laws

        true
      end

      def summary_for(id, entry)
        law = executable_definitions[id.to_s.upcase]
        details = law ? [law.ask, law.practice, law.fix] : []
        summary = details.find { |value| !value.to_s.strip.empty? }.to_s
        if summary.empty?
          sources = Array(entry["definition_sources"])
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
    end
  end
end
