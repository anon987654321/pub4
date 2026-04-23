# frozen_string_literal: true

require "yaml"
require "prism"

module Master
  module Scan
    module Rules
      # AxiomCoverageRule — meta-level rule. Checks that every axiom in
      # axioms.yml has at least one scan rule referencing it, and that all
      # @axiom_tags assignments in scan rules correspond to real axioms.
      #
      # Previously used a greedy regex /:([A-Z_]{3,})/ which matched any
      # uppercase symbol anywhere in the file — method-name symbols, hash
      # keys, constants — producing false positives. Now parses rule files
      # with Prism and extracts only the literal symbols assigned to
      # @axiom_tags.
      class AxiomCoverageRule < Rule
        def initialize(root: nil)
          super()
          @root        = root
          @id          = "axiom_coverage"
          @description = "Every axiom must have scan rule coverage; every tag must be a real axiom"
          @severity    = :warning
          @axiom_tags  = []
        end

        def check(code, path:)
          # Only run when scanning the scan rules directory itself.
          return [] unless path.include?("scan/rules") || path.include?("scan/rule.rb")
          return [] unless @root

          axiom_ids  = load_axiom_ids
          tagged_ids = load_tagged_ids
          findings   = []

          # Orphaned tags: in code but not in axioms.yml
          (tagged_ids - axiom_ids).each do |id|
            findings << finding(line: 1, message: "axiom_tag :#{id} has no entry in axioms.yml — define it or remove the tag")
          end

          # Uncovered axioms: in axioms.yml but no scan rule covers them
          (axiom_ids - tagged_ids).each do |id|
            findings << finding(line: 1, message: "axiom #{id} has no scan rule coverage — add a rule or accept as advisory")
          end

          findings
        end

        private

        def load_axiom_ids
          path = File.join(@root, "data", "axioms.yml")
          return [] unless File.exist?(path)

          data = YAML.safe_load_file(path)
          ids  = []
          ids += data.dig("kernel")&.keys || []
          ids += (data.dig("philosophy", "prioritized_top_25") || []).map { |a| a["id"] }
          ids += (data.dig("ux", "nielsen_heuristics") || []).map { |a| a["id"] }
          ids.map(&:to_s).uniq
        rescue StandardError
          []
        end

        # Parse each rule file with Prism and collect only the symbols in
        # the RHS of `@axiom_tags = [...]`. Falls back to an empty list on
        # parse error — never crashes the scan.
        def load_tagged_ids
          rules_dir = File.join(@root, "lib", "master", "scan", "rules")
          return [] unless Dir.exist?(rules_dir)

          Dir.glob(File.join(rules_dir, "*.rb")).flat_map { |f|
            extract_axiom_tags(File.read(f))
          }.uniq
        rescue StandardError
          []
        end

        def extract_axiom_tags(source)
          result = Prism.parse(source)
          return [] unless result.success?

          collector = TagCollector.new
          collector.visit(result.value)
          collector.tags
        rescue StandardError
          []
        end

        # Walks the Prism AST and collects symbols assigned to @axiom_tags.
        # Matches both forms:
        #   @axiom_tags = [:ONE_JOB, :CQS]
        #   @axiom_tags = %i[ONE_JOB CQS]
        class TagCollector < Prism::Visitor
          attr_reader :tags
          def initialize
            super
            @tags = []
          end

          def visit_instance_variable_write_node(node)
            if node.name == :@axiom_tags
              @tags.concat(collect_symbols(node.value))
            end
            super
          end

          private

          def collect_symbols(node)
            return [] unless node
            case node
            when Prism::ArrayNode
              node.elements.flat_map { |el| collect_symbols(el) }
            when Prism::SymbolNode
              [node.unescaped.to_s]
            else
              []
            end
          end
        end
      end
    end
  end
end
