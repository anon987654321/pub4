# frozen_string_literal: true

require_relative "../../master"
require_relative "detector"
require_relative "canonical_law_adapter"

module Master
  module Review
    module Scan
      # The Law population as the scanner runs it. Every Law is one ::Law.define
      # under law/ or law/detectors/; this loads them and builds, for each
      # enforceable one, the object the scanner calls: its detector class bound to
      # it, or the adapter that runs its `detect` or `check`.
      #
      # It replaces three ways in: LawDSL's generated classes, the
      # self-registering Scan::Law registry, and LawFactory's name-matched
      # constructors. They described one population three times and disagreed.
      module LawTree
        module_function

        def load!
          require File.join(Master::ROOT, "law", "definition") unless defined?(::Law::Definition)
          ::Law.load_all(File.join(Master::ROOT, "law"))
          ::Law.definitions
        end

        def definitions = load!.values

        def ids = definitions.map { |definition| definition.id.to_s }

        # One scanner object per enforceable Law that has anything to run.
        def build(root: Master::ROOT, agent: nil, ecology: nil)
          definitions.select(&:enforceable?).filter_map do |definition|
            if definition.detector
              definition.detector.build(definition, root:, agent:, ecology:)
            elsif definition.scannable?
              CanonicalLawAdapter.new(definition)
            end
          end
        end

        def find(id, root: Master::ROOT, agent: nil, ecology: nil)
          definition = load![id.to_sym] || ::Law.definitions.values.find { |law| law.id.to_s.casecmp?(id.to_s) }
          return unless definition

          if definition.detector
            definition.detector.build(definition, root:, agent:, ecology:)
          else
            CanonicalLawAdapter.new(definition)
          end
        end
      end
    end
  end
end

Master::Review::Scan::LawTree.load!
