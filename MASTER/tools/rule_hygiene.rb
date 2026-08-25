# frozen_string_literal: true

# Integrity of the rule catalogue itself: ids, aliases, and the metadata every
# report quotes.
#
# Three checks, each one that survived being measured. Two more were proposed and
# died on contact with the data, which is worth recording so nobody re-proposes
# them:
#
#   "every alias must resolve to a live id" is backwards. An alias IS a retired
#   id — KISS carries long_method, god_class, nesting_depth and arity because it
#   absorbed them. An alias pointing at a live rule is the defect, not the
#   reverse.
#
#   "a folder must not share a name with a file inside it" flags a normal Ruby
#   idiom. rexml/rexml.rb, drb/drb.rb and mail/mail.rb all do it, and so do
#   law/law.rb and lib/cli/cli.rb.
#
#   ruby MASTER/tools/rule_hygiene.rb
#   ruby MASTER/tools/rule_hygiene.rb --json

require "yaml"
require "json"

module Pub4
  module RuleHygiene
    MASTER = File.expand_path("..", __dir__)
    CEILING = File.join(MASTER, "data", "rule_hygiene.yml")

    module_function

    def yaml_rules
      data = YAML.load_file(File.join(MASTER, "data", "rules.yml"))
      found = []
      walk = lambda do |node|
        case node
        when Array then node.each(&walk)
        when Hash
          found << node if node["id"]
          node.each_value(&walk)
        end
      end
      walk.call(data)
      found
    end

    def law_ids
      Dir.glob(File.join(MASTER, "law", "*.rb"))
         .flat_map { |p| File.read(p, encoding: "UTF-8").scrub.scan(/Law\.define\(:(\w+)\)/).flatten }
    end

    def dsl_ids
      Dir.glob(File.join(MASTER, "lib", "review", "scan", "rules", "*.rb"))
         .flat_map { |p| File.read(p, encoding: "UTF-8").scrub.scan(/RuleDSL\.rule\s+:(\w+)/).flatten }
    end

    def all_ids = (yaml_rules.map { |r| r["id"] } + law_ids + dsl_ids).compact

    # Two ids differing only by case are two rules as far as every registry is
    # concerned and one rule as far as a reader is concerned. Findings, priors
    # and exemptions key on the id, so the pair silently splits a rule's history.
    def id_case_collisions
      all_ids.group_by(&:downcase).select { |_, v| v.uniq.size > 1 }.map { |_, v| v.uniq }
    end

    # An alias naming a rule that still exists makes a lookup ambiguous: DRY
    # claims duplicate_code, and duplicate_code is its own live rule. One of the
    # two is a fold that never finished.
    def alias_shadows_live_rule
      live = all_ids.map(&:downcase)
      yaml_rules.flat_map do |r|
        Array(r["aliases"]).select { |a| live.include?(a.to_s.downcase) }
                           .map { |a| { rule: r["id"], alias_name: a.to_s } }
      end
    end

    # A rule with neither tier nor severity cannot be sorted, filtered or
    # prioritised, and every count that groups by either quietly omits it.
    def missing_metadata
      yaml_rules.select { |r| r["tier"].to_s.strip.empty? && r["severity"].to_s.strip.empty? }
                .map { |r| r["id"] }
    end

    # One id, two definitions, two wordings, and no way for a reader to tell
    # which governs. FAIL_VISIBLY had three — soul said "never rescue Exception",
    # law/ said "catch specific errors, log context, re-raise", rules.yml said
    # "surface errors immediately" — and each had its own detector or none.
    #
    # The rule for resolving one: whichever population holds the detector owns
    # the wording. A population that only restates it is the copy. soul is the
    # exception in one direction only, for an axiom nothing can check.
    def cross_population_duplicates
      soul = YAML.safe_load_file(File.join(MASTER, "data", "soul.yml"))
                 .dig("absolute", "rules").to_h.keys.map(&:upcase)
      detectable = yaml_rules.select { |r| %w[detect_semantic detect_structural detect_lexical].any? { |k| r[k].to_s.strip != "" } }
                             .map { |r| r["id"].to_s.upcase }
      homes = Hash.new { |h, k| h[k] = [] }
      { "law/" => law_ids.map(&:upcase), "RuleDSL" => dsl_ids.map(&:upcase),
        "rules.yml" => detectable, "soul" => soul }.each do |name, ids|
        ids.each { |id| homes[id] << name }
      end
      homes.select { |_, where| where.uniq.size > 1 }
           .map { |id, where| { rule: id, homes: where.uniq } }
           .sort_by { |h| h[:rule] }
    end

    def ceilings = YAML.safe_load_file(CEILING)

    def report
      { id_case_collisions: id_case_collisions,
        alias_shadows_live_rule: alias_shadows_live_rule,
        missing_metadata: missing_metadata,
        cross_population_duplicates: cross_population_duplicates }
    end

    def run(json: false)
      r = report
      return (puts JSON.pretty_generate(r)) || true if json

      r[:id_case_collisions].each do |pair|
        warn "rule_hygiene: #{pair.inspect} differ only by case — two ids, one rule, split history"
      end
      r[:alias_shadows_live_rule].each do |a|
        warn "rule_hygiene: #{a[:rule]} claims alias `#{a[:alias_name]}`, which is itself a live rule — an unfinished fold"
      end
      unless r[:missing_metadata].empty?
        puts "rule_hygiene: #{r[:missing_metadata].size} rule(s) declare neither tier nor severity"
      end

      c = ceilings
      over = r.keys.select { |k| r[k].size > c.fetch(k.to_s) }
      over.each { |k| warn "rule_hygiene: exceeds baseline — #{k} #{r[k].size} > #{c.fetch(k.to_s)}" }
      puts "rule_hygiene: #{r.map { |k, v| "#{k} #{v.size}" }.join(', ')}"
      over.empty?
    end
  end
end

if $PROGRAM_NAME == __FILE__
  ok = Pub4::RuleHygiene.run(json: ARGV.include?("--json"))
  exit(ok ? 0 : 1)
end
