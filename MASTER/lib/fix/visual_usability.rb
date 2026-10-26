# frozen_string_literal: true

module Master
  module Fix
    module VisualUsability
      # The laws remain ONE_SOURCE in law/. This list only declares which
      # constitutional laws are relevant to rendered product review.

      module_function

      def ids
        load_laws!
        executable = ::Law.definitions.keys.map { |id| id.to_s.upcase }
        inline = Master::Review::Scan::Law.registry.filter_map do |klass|
          next unless klass.respond_to?(:dsl_id) && !klass.dsl_id.to_s.empty?

          klass.dsl_id.to_s.upcase
        end
        catalogue = Master.law_entries.filter_map { |row| row["id"]&.to_s&.upcase }
        (catalogue + executable + inline).uniq.sort.freeze
      end

      def context
        ids.map { |id| line(id) }.join("\n")
      end

      def load_laws!
        require File.expand_path("../../law/definition", __dir__)
        ::Law.load_all(File.expand_path("../../law", __dir__)) if ::Law.definitions.empty?
        require_relative "../review/scan/law_dsl" unless defined?(Master::Review::Scan::LawDSL)
      end

      def constitutional_laws
        @constitutional_laws ||= Master.law_entries.to_h { |entry| [entry.fetch("id").to_s.upcase, entry] }
      end

      def inline_laws
        @inline_laws ||= Master::Review::Scan::Law.registry.filter_map do |klass|
          next unless klass.respond_to?(:dsl_id) && !klass.dsl_id.to_s.empty?

          [klass.dsl_id.to_s.upcase, Master::Review::Scan::LawFactory.build(klass, root: Master::ROOT)]
        end.to_h
      end

      def line(id)
        key = id.to_s.upcase
        law = ::Law.definitions[key.to_sym] || ::Law.definitions[key.to_s]
        return "#{key}: #{law.ask} Fix: #{law.fix}" if law

        inline = inline_laws[key]
        return "#{key}: #{inline.description}" if inline

        row = constitutional_laws[key]
        return "#{key}: #{row["statement"] || row["ask"] || row["source"]}" if row

        raise KeyError, "visual review referenced unknown Law #{key}"
      end
    end
  end
end
