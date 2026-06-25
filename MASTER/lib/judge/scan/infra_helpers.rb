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
          Judge::Scan::Rule.registry.select(&:auto_build?).each { |klass| scanner.add_rule(klass.new) }
          scanner.add_rule(Judge::Scan::Rules::CoChangeCouplingRule.new(root:, ecology:))
          scanner.add_rule(Judge::Scan::Rules::RuleCoverageRule.new(root:))
          scanner.add_rule(Judge::Scan::Rules::RubocopRule.new(root:))
          scanner.add_rule(Judge::Scan::Rules::ReekRule.new(root:))
          scanner.add_rule(Judge::Scan::Rules::InterconnectRule.new(root:))
          scanner.add_rule(Judge::Scan::Rules::YamlDeclarativeRule.new(root:))
          scanner.add_rule(Judge::Scan::Rules::VetoPatternRule.new(root:))
          scanner.add_rule(Judge::Scan::Rules::SemanticRule.new(agent:))
          scanner.add_rule(Judge::Scan::Rules::AdversarialRule.new(agent:))
          scanner.add_rule(Judge::Scan::Rules::CommentDriftRule.new(agent:))
          scanner.add_rule(Judge::Scan::Rules::AstOmissionRule.new(root:))
          scanner
        end
      end
    end
  end
end