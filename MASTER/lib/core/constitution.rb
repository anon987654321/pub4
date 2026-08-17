# frozen_string_literal: true

require "yaml"
require_relative "constitution_rules"

module Master::Core
  # Constitution — the single gate. Every Effect the agent proposes folds
  # through the rules here before the World performs anything. This is where the
  # old council, scan, judge, biases, veto, evidence, sharp_edges, and the Guard
  # all live now: not as subsystems, but as rules over effects. One `admit`.
  #
  # A rule watches a verb, judges an effect against the live data/*.yml (the one
  # source), and returns Allow (pass), Revise (rewrite for the rules after it),
  # or Block (stop). admit folds them: the first Block wins; Revises carry
  # forward; what comes out the end is the effect the World will perform.
  class Constitution
    Rule = Data.define(:id, :verbs, :judge) do
      def watches?(verb) = verbs.include?(verb)
    end

    REPO_TREES = %w[MASTER RAILS OPENBSD STUDIO bin dotfiles].freeze
    FORBIDDEN_BASENAMES = %w[summary.md analysis.md report.md todo.md notes.md changelog.md].freeze
    TWO_HATS_LINES = 200
    SCOPE_TREES = 3
    SCOPE_SECONDS = 1_800
    FEAT_RX = /\b(feat|fix|add|ship|implement)\b/i
    REFACTOR_RX = /\b(refactor|cleanup|clean up|restructure|rewrite)\b/i
    SYNTAX_CHECK_TIMEOUT_S = 5

    def self.load(data_dir:, verify: nil)
      rules_data = YAML.safe_load_file(File.join(data_dir, "rules.yml"), aliases: true)
      rules = ConstitutionRules.build_rules(rules_data, verify:)
      new(rules:)
    end

    def initialize(rules:)
      @rules = rules
    end

    def admit(effect, memory)
      @rules.each do |rule|
        next unless rule.watches?(effect.verb)

        case rule.judge.call(effect, memory)
        in Verdict::Block => b then return b
        in Verdict::Revise(effect: revised) then effect = revised
        else next
        end
      end
      Verdict::Allow.new(effect:)
    end

    def self.immutable_paths_rule(immutable)
      ConstitutionRules.immutable_paths_rule(immutable)
    end
  end
end
