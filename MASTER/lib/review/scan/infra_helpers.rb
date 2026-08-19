# frozen_string_literal: true

# Single wiring layer for the scan rule registry (rules.yml:39 intent).
module Master
  module Review
    module Scan
      module InfraHelpers
        module_function

        def build_scanner(root:, agent: nil, bus: nil, ecology: nil)
          Review::Scan::RuleDSL
          wf = Master.load_yaml(Master.limits_path) rescue {}
          sleep_s = ENV["MASTER_AUTOFIX"] == "1" ? wf.dig("autoloop", "scan_file_sleep_s").to_f : 0
          scanner = Review::Scan::Scanner.new(event_bus: bus, file_sleep_s: sleep_s)
          Review::Scan::Rule.registry.select(&:auto_build?).each do |klass|
            scanner.add_rule(Review::Scan::RuleFactory.build(klass, root:, agent:, ecology:))
          end
          %w[
            CoChangeCouplingRule RuleCoverageRule RubocopRule ReekRule InterconnectRule
            YamlDeclarativeRule VetoPatternRule LawBridgeRule SemanticRule AdversarialRule CommentDriftRule AstOmissionRule
            LibRootDisciplineRule FileSprawlRule
          ].each do |name|
            klass = Review::Scan::Rules.const_get(name)
            scanner.add_rule(Review::Scan::RuleFactory.build(klass, root:, agent:, ecology:))
          end
          scanner
        end
      end
    end
  end
end
