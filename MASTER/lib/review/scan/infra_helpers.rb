# frozen_string_literal: true

# Single wiring layer for the scan rule registry (rules.yml:39 intent).
module Master
  module Review
    module Scan
      module InfraHelpers
        module_function

        # MASTER_SCAN_DETERMINISTIC=1 withholds the agent, which is the only
        # thing the model-backed rules need: AdversarialRule, SemanticRule and
        # CommentDriftRule each already answer `return [] unless @agent`, so
        # this switches them off through the guard they carry rather than adding
        # a second way to disable a rule.
        #
        # It exists because `bin/gate` calls /scan its *lexical* tier and says so
        # in its own header — "deterministic detectors, no model" — while the
        # runtime hands that scanner an agent (builder/ai_boot.rb), so every file
        # was costing a model round trip. Measured on this tree: `lib/io`, 46
        # files, 1.4s with no agent and 395s for the first FIVE files with one,
        # which is why the stage had never once reached a verdict inside its
        # 1200s timeout. Opt-in, so nothing changes for an ordinary /scan.
        def build_scanner(root:, agent: nil, bus: nil, ecology: nil)
          agent = nil if ENV["MASTER_SCAN_DETERMINISTIC"] == "1"
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
