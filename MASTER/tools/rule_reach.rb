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

module Operator
  module RuleReach
    MASTER_DIR = File.expand_path("..", __dir__)
    CEILING = File.join(MASTER_DIR, "data", "rules.yml")

    module_function

    def rules
      $LOAD_PATH.unshift(File.join(MASTER_DIR, "lib")) unless $LOAD_PATH.include?(File.join(MASTER_DIR, "lib"))
      require "master"
      Master.flatten_rules(Master.load_rules(root: MASTER_DIR).fetch("rules", {}))
    end

    # A rule is mechanical if something can run it: a lexical or structural
    # detector in the yml, a law in law/, or a class in the scanner registry —
    # under its own id or under the one it folded into.
    #
    # RuleRegistryAudit owns the question, because three gate banners print a
    # count of the same population and a second spelling here answered 115 where
    # theirs answered 107. Asking rather than restating is what keeps them one
    # number.
    def mechanical(all)
      rules # boots the runtime so the audit and its laws resolve
      Master::Review::Scan::RuleRegistryAudit.new(root: MASTER_DIR).mechanical(all)
    end

    # Mirrors SemanticRule#load_semantic_rules. Kept in step by test_rule_reach.
    def prompted(all)
      all.select { |rule| rule["detect_semantic"] }
         .reject { |rule| rule["severity"] == "info" && rule["mode"] != "opportunity" && rule["tier"] != "kernel" }
    end

    def unreachable(all = rules) = all - mechanical(all) - prompted(all)

    def ceiling
      rules # boots the runtime, so Master.law resolves
      Master.law("rule_ratchets", root: MASTER_DIR).dig("reach", "unreachable") || 0
    end

    def run(ratchet: false, json: false)
      all = rules
      out = unreachable(all)
# `puts` returns nil and this handed that straight to Kernel#exit, so
# --json printed correct JSON and then died with a TypeError.
if json
  puts(JSON.pretty_generate(total: all.size, mechanical: mechanical(all).size,
                            prompted: prompted(all).size, unreachable: out.map { |r| r["id"] }))
  return 0
end

# "unreachable" read as "no detector", which is what the advice below used
# to assume. Measured 2026-08-25: all 58 declare a detect_semantic and
# every one is info severity, so what drops them is the exclusion this
# file's own header describes. Naming the filter names the lever.
puts "rule_reach: #{all.size} rules — #{mechanical(all).size} without a model, " \
     "#{prompted(all).size} with one, #{out.size} dropped by the info filter (ceiling #{ceiling})"
      return record(out.size) if ratchet && out.size < ceiling

      return 0 unless out.size > ceiling

out.first(10).each { |rule| puts "  #{rule['id']} (#{rule['severity']}) declares only a semantic detector at info" }
puts "rule_reach: raise its severity so the prompt keeps it, give it a detect_lexical, or drop it — " \
     "law nothing can enforce is a claim"
      1
    end

    def record(count)
      # A line rewrite, not a YAML dump: rules.yml is mostly the argument for
      # its numbers, and to_yaml would write the numbers and drop the argument.
      lines = File.readlines(CEILING)
      i = lines.index { |line| line.match?(/^\s+unreachable: \d+\s*$/) }
      raise "rules.yml: no rule_ratchets.reach.unreachable line" unless i

      lines[i] = lines[i].sub(/\d+/) { count.to_s }
      File.write(CEILING, lines.join)
      puts "rule_reach: recorded #{count} as the new low"
      0
    end
  end
end

if $PROGRAM_NAME == __FILE__
  exit Operator::RuleReach.run(ratchet: ARGV.include?("--ratchet"), json: ARGV.include?("--json"))
end
