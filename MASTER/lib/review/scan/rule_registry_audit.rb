# frozen_string_literal: true

module Master
  module Review
    module Scan
      # Audits rules.yml declarative corpus vs Ruby scanner registry.
      class RuleRegistryAudit
        Report = Data.define(:yaml_rules, :registry_ids, :kernel_ids, :lexical_wired, :lexical_unwired,
                             :semantic_only, :structural_unwired, :dep_graph_gaps) do
          # "clean" over 99 rules and "clean" over 225 are different claims, and
          # until now they printed identically everywhere except rake constitution.
          def coverage_line = "#{yaml_rules - semantic_only.size} of #{yaml_rules} rules active " \
                              "(#{semantic_only.size} semantic need an LLM agent; none attached)"

          def adherence_pct
            return 100.0 if yaml_rules.zero?
            lexical_total = lexical_wired.size + lexical_unwired.size
            lexical_pct = lexical_total.zero? ? 100.0 : ((lexical_wired.size + lexical_unwired.size) * 100.0 / lexical_total)
            registry_pct = (registry_ids.size * 100.0 / [yaml_rules, 1].max)
            ((lexical_pct * 0.55) + (registry_pct * 0.45)).round(1)
          end

          def lines
            [
              "rules audit — #{yaml_rules} yaml ids, #{registry_ids.size} ruby rules, #{adherence_pct}% wired",
              "  kernel yaml: #{kernel_ids.size}",
              "  lexical wired (ruby+yaml bridge): #{lexical_wired.size}",
              "  lexical unwired: #{lexical_unwired.size}",
              "  semantic-only: #{semantic_only.size}",
              "  structural unwired: #{structural_unwired.size}",
              "  rule_deps gaps: #{dep_graph_gaps.size}",
            ]
          end
        end

        def initialize(root: Master::ROOT)
          @root = root
        end

        def call
          Review::Scan::RuleDSL
          yaml_entries = load_yaml_rules
          registry = build_registry_ids
          c = classify_yaml_entries(yaml_entries, registry)

          Report.new(
            yaml_rules: c[:yaml_ids].size,
            registry_ids: registry,
            kernel_ids: c[:kernel],
            lexical_wired: c[:lexical_wired],
            lexical_unwired: c[:lexical_unwired],
            semantic_only: c[:semantic_only],
            structural_unwired: c[:structural_unwired],
            dep_graph_gaps: ungraphed_rule_ids(registry),
          )
        end

        def ungraphed_rule_ids(registry = nil)
          Review::Scan::RuleDSL
          registry ||= Review::Scan::Rule.registry
            .map { |klass| RuleFactory.build(klass, root: @root).id.to_s }
            .to_set
          registry = registry.map { |id| id.to_s.downcase }.to_set
          deps = Master.load_yaml(File.join(@root, "data", "rule_deps.yml")).dig("deps") || {}
          graphed = deps.keys.map { |k| k.to_s.downcase }.to_set
          registry.reject { |id| graphed.include?(id) }.sort
        end

        private

        def load_yaml_rules
          Master.flatten_rules(Master.load_rules(root: @root).fetch("rules", {}))
        end

        def build_registry_ids
          Review::Scan::Rule.registry
            .reject { |klass| RuleFactory.bridge_class?(klass) }
            .map { |klass| RuleFactory.build(klass, root: @root).id.to_s.downcase }
            .to_set
        end

        def classify_yaml_entries(yaml_entries, registry)
          yaml_ids = yaml_entries.map { |r| r["id"].to_s.downcase }
          kernel = yaml_entries.select { |r| r["tier"] == "kernel" }.map { |r| r["id"].to_s.downcase }

          lexical_yaml = yaml_entries.select { |r| r["detect_lexical"] }
          lexical_wired = lexical_yaml.select { |r| registry.include?(r["id"].to_s.downcase) }
          lexical_unwired = lexical_yaml.reject { |r| registry.include?(r["id"].to_s.downcase) }

          semantic_only = yaml_entries.select { |r| r["detect_semantic"] && !r["detect_lexical"] && !r["detect_structural"] }
          structural_unwired = yaml_entries.select { |r| r["detect_structural"] && !registry.include?(r["id"].to_s.downcase) }

          {
            yaml_ids:, kernel:,
            lexical_wired: lexical_wired.map { |r| r["id"] },
            lexical_unwired: lexical_unwired.map { |r| r["id"] },
            semantic_only: semantic_only.map { |r| r["id"] },
            structural_unwired: structural_unwired.map { |r| r["id"] }
          }
        end
      end
    end
  end
end
