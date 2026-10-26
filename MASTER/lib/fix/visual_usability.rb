# frozen_string_literal: true

module Master
  module Fix
    module VisualUsability
      # The laws remain ONE_SOURCE in law/. This list only declares which
      # constitutional laws are relevant to rendered product review.

      module_function

      def ids
        load_laws!
        catalogue = law_catalogue.keys.map { |id| id.to_s.upcase }
        executable = ::Law.definitions.values.map { |law| law.id.to_s.upcase }
        scanner = scanner_laws.keys
        (catalogue + executable + scanner).uniq.sort.freeze
      end

      def context
        ids.map { |id| line(id) }.join("\n")
      end

      def load_laws!
        require File.expand_path("../../law/definition", __dir__)
        ::Law.load_all(File.expand_path("../../law", __dir__)) if ::Law.definitions.empty?
        require_relative "../review/scan/law_dsl" unless defined?(Master::Review::Scan::LawDSL)
      end

      def law_catalogue
        @law_catalogue ||= Master.law("law_catalogue").fetch("entries")
      end

      def scanner_laws
        @scanner_laws ||= Master::Review::Scan::Law.registry.filter_map do |klass|
          law = Master::Review::Scan::LawFactory.build(klass, root: Master::ROOT)
          [law.id.to_s.upcase, law]
        end.to_h
      end

      def line(id)
        key = id.to_s.upcase
        law = ::Law.definitions[key.to_sym] || ::Law.definitions[key.to_s]
        return "#{key}: #{law.ask} Fix: #{law.fix}" if law

        scanner = scanner_laws[key]
        if scanner
          description = scanner.respond_to?(:description) ? scanner.description.to_s.strip : ""
          description = "Assess #{key} for a clear breach and a concrete improvement." if description.empty?
          return "#{key}: #{description}"
        end

        row = law_catalogue[key] || law_catalogue.find { |name, _entry| name.to_s.upcase == key }&.last
        return "#{key}: #{Array(row["definition_sources"]).join(", ")} #{Array(row["detector_sources"]).join(", ")}".strip if row

        raise KeyError, "visual review referenced unknown Law #{key}"
      end
    end
  end
end
