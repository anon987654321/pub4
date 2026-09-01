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
    MASTER_DIR = File.expand_path("..", __dir__)
    CEILING = File.join(MASTER_DIR, "data", "rules.yml")

    module_function

    def rules
      $LOAD_PATH.unshift(File.join(MASTER_DIR, "lib")) unless $LOAD_PATH.include?(File.join(MASTER_DIR, "lib"))
      require "master"
      Master.flatten_rules(Master.load_rules(root: MASTER_DIR).fetch("rules", {}))
    end

    # A rule is mechanical if something can run it. law/ is one of those places
    # now: a migrated rule has detect_lexical: ~ in the yml and a detector, a bad
    # fixture and a good one in law/<id>.rb. Counting only the yml column reported
    # eighty-one of them as reaching nothing on the day they became the only rules
    # in the tree that prove themselves before they may judge anything.
    # Asked of the loaded registry, not of the source text. Scanning for a
    # literal `Law.define(:ID)` reads only the laws whose id is spelled in the
    # file, and law/prose.rb generates its four from data/rules.yml — one pair
    # per natural language — so a grep saw none of them and called two live,
    # proving, firing laws unreachable. Loading is what running does.
    def enacted
      dir = File.join(MASTER_DIR, "law")
      return Set.new unless Dir.exist?(dir)

      require File.join(dir, "law")
      ::Law.load_all(dir) if ::Law.rules.empty?
      ::Law.rules.keys.map(&:to_s).to_set
    rescue StandardError
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
        .filter_map { |klass| Master::Review::Scan::RuleFactory.registry_id(klass, root: MASTER_DIR)&.upcase }
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
  exit Pub4::RuleReach.run(ratchet: ARGV.include?("--ratchet"), json: ARGV.include?("--json"))
end
