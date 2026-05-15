# frozen_string_literal: true

module Master
  module Plugins
  module Judge
    def self.configure(base, root: Dir.pwd, agent: nil, bus: nil, **_opts)
      scanner = Master::Judge::Scan::Scanner.new(event_bus: bus)
      Master::Judge::Scan::Rule.registry.select(&:auto_build?).each { |k| scanner.add_rule(k.new) }
      scanner.add_rule(Master::Judge::Scan::Rules::RuleCoverageRule.new(root:))
      scanner.add_rule(Master::Judge::Scan::Rules::RubocopRule.new(root:))
      scanner.add_rule(Master::Judge::Scan::Rules::ReekRule.new(root:))
      scanner.add_rule(Master::Judge::Scan::Rules::InterconnectRule.new(root:))
      scanner.add_rule(Master::Judge::Scan::Rules::SemanticRule.new(agent:))
      scanner.add_rule(Master::Judge::Scan::Rules::AdversarialRule.new(agent:))
      scanner.add_rule(Master::Judge::Scan::Rules::CommentDriftRule.new(agent:))
      scanner.add_rule(Master::Judge::Scan::Rules::AstOmissionRule.new(root:))
      scanner
    end

    Master::Plugin.register(:judge, self)
  end
  end
end
