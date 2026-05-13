# frozen_string_literal: true

require "prism"

module Master
  module Judge
  module Scan
    module Rules
      # Every rule ID in rules.yml must have scan rule coverage; every @rule_tags
      # symbol must name a real rule ID. Orphaned tags and uncovered rules both signal drift.
      class RuleCoverageRule < Rule
        RULE_ID           = "rule_coverage"
        DESCRIPTION       = "Every rule must have scan rule coverage; every tag must be a real rule"
        RULES_YML_PATH    = File.join("data", "rules.yml")
        SCAN_RULES_DIR    = File.join("lib", "master", "judge", "scan", "rules")
        RULE_TAGS_VAR    = :@rule_tags
        ORPHANED_TAG_MSG  = "axiom_tag :%s has no entry in rules.yml — define it or remove the tag"
        UNCOVERED_RULE_MSG = "rule %s has no scan rule coverage — add a rule or accept as advisory"
        ORPHAN_FILE_MSG   = "scan rule file %s does not define a class inheriting from Master::Judge::Scan::Rule — registry will skip it silently"

        def initialize(root: nil)
          super()
          @root        = root
          @id          = RULE_ID
          @description = DESCRIPTION
          @severity    = :warning
          @rule_tags  = []
        end

        def self.auto_build? = false

        def check(code, path:)
          return [] unless path.include?(SCAN_RULES_DIR) || path.include?("scan/rule.rb")
          return [] unless @root

          axiom_ids  = load_axiom_ids
          tagged_ids = load_tagged_ids
          findings   = []

          (tagged_ids - axiom_ids).each do |id|
            findings << finding(line: 1, message: format(ORPHANED_TAG_MSG, id))
          end

          (axiom_ids - tagged_ids).each do |id|
            findings << finding(line: 1, message: format(UNCOVERED_RULE_MSG, id))
          end

          orphan_rule_files.each do |file|
            findings << finding(line: 1, message: format(ORPHAN_FILE_MSG, file))
          end

          findings
        end

        def orphan_rule_files
          full_rules_dir = File.join(@root, SCAN_RULES_DIR)
          return [] unless Dir.exist?(full_rules_dir)
          Dir.glob(File.join(full_rules_dir, "*.rb")).reject { |f| inherits_from_rule?(File.read(f)) }
             .map { |f| File.basename(f) }
        rescue StandardError
          []
        end

        def inherits_from_rule?(source)
          result = Prism.parse(source)
          return true unless result.success?
          finder = SuperclassFinder.new
          finder.visit(result.value)
          finder.found
        rescue StandardError
          true
        end

        private

        def load_axiom_ids
          full_path = File.join(@root, RULES_YML_PATH)
          return [] unless File.exist?(full_path)

          data = Master.load_yaml(full_path)
          all_rules = (data["rules"] || {}).values.flatten
          all_rules.map { |r| r["id"] }.compact.uniq
        rescue StandardError
          []
        end

        def load_tagged_ids
          full_rules_dir = File.join(@root, SCAN_RULES_DIR)
          return [] unless Dir.exist?(full_rules_dir)

          Dir.glob(File.join(full_rules_dir, "*.rb")).flat_map { |f|
            extract_rule_tags(File.read(f))
          }.uniq
        rescue StandardError
          []
        end

        def extract_rule_tags(source)
          result = Prism.parse(source)
          return [] unless result.success?

          collector = TagCollector.new
          collector.visit(result.value)
          collector.tags
        rescue StandardError
          []
        end

        class SuperclassFinder < Prism::Visitor
          attr_reader :found

          def initialize
            super
            @found = false
          end

          def visit_class_node(node)
            sc = node.superclass
            if sc && rule_superclass?(sc)
              @found = true
            end
            super
          end

          private

          def rule_superclass?(node)
            case node
            when Prism::ConstantReadNode
              node.name == :Rule
            when Prism::ConstantPathNode
              node.name == :Rule
            else
              false
            end
          end
        end

        class TagCollector < Prism::Visitor
          attr_reader :tags

          def initialize
            super
            @tags = []
          end

          def visit_instance_variable_write_node(node)
            if node.name == RULE_TAGS_VAR
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
end
