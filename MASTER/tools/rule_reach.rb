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

    # A rule is mechanical if something can run it. law/ is one of those places
    # now: a migrated rule has detect_lexical: ~ in the yml and a detector, a bad
    # fixture and a good one in law/<id>.rb. Counting only the yml column reported
    # eighty-one of them as reaching nothing on the day they became the only rules
    # in the tree that prove themselves before they may judge anything.
    def enacted
      dir = File.join(ROOT, "law")
      return Set.new unless Dir.exist?(dir)

      Dir.glob(File.join(dir, "*.rb")).flat_map { |f| File.read(f).scan(/Law\.define\(:(\w+)\)/) }.flatten.to_set
    end

    # folded_into names the law that carries a rule whose detector was identical
    # to another's. The id survives so principle_map can still trace it; the
    # detector does not exist twice. Reachable through the law it folded into.
    def mechanical(all)
      laws = enacted
      regs = registry_ids
      all.select do |rule|
        rule["detect_lexical"] || rule["detect_structural"] ||
          laws.include?(rule["id"].to_s) || laws.include?(rule["folded_into"].to_s) ||
          regs.include?(rule["id"].to_s.upcase) || regs.include?(rule["folded_into"].to_s.upcase)
      end
    end

    # The registry (RuleDSL classes) is the third rule population. MAGIC_COLOR
    # lives only there since its law twin retired; counting law/ and the yml
    # columns alone reported it as law no configuration can run.
    def registry_ids
      require "review/scan/rule_dsl"
      Master::Review::Scan::Rule.registry
        .filter_map { |klass| Master::Review::Scan::RuleFactory.registry_id(klass, root: ROOT)&.upcase }
        .to_set
    rescue StandardError
      Set.new
    end

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
