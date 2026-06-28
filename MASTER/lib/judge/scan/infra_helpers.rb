# frozen_string_literal: true

# Single wiring layer for the scan rule registry (rules.yml:39 intent).
module Master
  module Judge
    module Scan
      module InfraHelpers
        module_function

        def build_scanner(root:, agent: nil, bus: nil, ecology: nil)
          Judge::Scan::RuleDSL
          wf = Master.load_yaml(Master.limits_path) rescue {}
          sleep_s = wf.dig("autoloop", "scan_file_sleep_s").to_f
          scanner = Judge::Scan::Scanner.new(event_bus: bus, file_sleep_s: sleep_s)
          Judge::Scan::Rule.registry.select(&:auto_build?).each do |klass|
            scanner.add_rule(Judge::Scan::RuleFactory.build(klass, root:, agent:, ecology:))
          end
          %w[
            CoChangeCouplingRule RuleCoverageRule RubocopRule ReekRule InterconnectRule
            YamlDeclarativeRule VetoPatternRule SemanticRule AdversarialRule CommentDriftRule AstOmissionRule
          ].each do |name|
            klass = Judge::Scan::Rules.const_get(name)
            scanner.add_rule(Judge::Scan::RuleFactory.build(klass, root:, agent:, ecology:))
          end
          scanner
        end
      end
    end
  end
end
