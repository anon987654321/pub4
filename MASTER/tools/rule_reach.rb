# frozen_string_literal: true

# How many rules can fire, and under what conditions.
#
# A rule in data/rules.yml reaches code three ways: a lexical detector, a
# structural one, or a semantic prompt folded into SemanticRule's single call
# per file. A rule with none of those is law that no configuration can enforce,
# and it counts toward "225 rules" in every report that quotes the total.
#
#   ruby MASTER/tools/rule_reach.rb
#   ruby MASTER/tools/rule_reach.rb --ratchet
#
# The semantic prompt drops info-severity violations deliberately — they double
# the token cost of every file for findings nobody acts on. That exclusion is a
# decision, so this counts its result rather than arguing with it, and refuses
# to let the unreachable set grow.

require "yaml"
require "json"

module Pub4
  module RuleReach
    ROOT = File.expand_path("..", __dir__)
    CEILING = File.join(ROOT, "data", "rule_reach.yml")

    module_function

    def rules
      $LOAD_PATH.unshift(File.join(ROOT, "lib")) unless $LOAD_PATH.include?(File.join(ROOT, "lib"))
      require "master"
      Master.flatten_rules(Master.load_rules(root: ROOT).fetch("rules", {}))
    end

    def mechanical(all) = all.select { |rule| rule["detect_lexical"] || rule["detect_structural"] }

    # Mirrors SemanticRule#load_semantic_rules. Kept in step by test_rule_reach.
    def prompted(all)
      all.select { |rule| rule["detect_semantic"] }
         .reject { |rule| rule["severity"] == "info" && rule["mode"] != "opportunity" && rule["tier"] != "kernel" }
    end

    def unreachable(all = rules) = all - mechanical(all) - prompted(all)

    def ceiling = File.exist?(CEILING) ? YAML.safe_load_file(CEILING).fetch("unreachable", 0) : 0

    def run(ratchet: false, json: false)
      all = rules
      out = unreachable(all)
      return puts(JSON.pretty_generate(total: all.size, mechanical: mechanical(all).size,
                                       prompted: prompted(all).size, unreachable: out.map { |r| r["id"] })) if json

      puts "rule_reach: #{all.size} rules — #{mechanical(all).size} without a model, " \
           "#{prompted(all).size} with one, #{out.size} unreachable (ceiling #{ceiling})"
      return record(out.size) if ratchet && out.size < ceiling

      return 0 unless out.size > ceiling

      out.first(10).each { |rule| puts "  #{rule['id']} (#{rule['severity']}) reaches no detector" }
      puts "rule_reach: give it a detect_lexical, or drop it — law nothing can enforce is a claim"
      1
    end

    def record(count)
      File.write(CEILING, { "unreachable" => count }.to_yaml)
      puts "rule_reach: recorded #{count} as the new low"
      0
    end
  end
end

if $PROGRAM_NAME == __FILE__
  exit Pub4::RuleReach.run(ratchet: ARGV.include?("--ratchet"), json: ARGV.include?("--json"))
end
