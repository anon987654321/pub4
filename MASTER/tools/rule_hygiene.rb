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
#   law/law.rb and lib/cli/session.rb.
#
#   ruby MASTER/tools/rule_hygiene.rb
#   ruby MASTER/tools/rule_hygiene.rb --json

require "yaml"
require "json"

module Pub4
  module RuleHygiene
    MASTER = File.expand_path("..", __dir__)

    module_function

    # Through the accessor, not a second load of rules.yml: the file this tool
    # audits has to be the file the runtime reads, and reader_singularity is
    # the ratchet that keeps those two from drifting apart.
    def master_rules
      lib = File.join(MASTER, "lib")
      $LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
      require "master"
      Master.load_rules(root: MASTER)
    end

    # The two populations rules.yml declares, and no third. A hand-rolled walk
    # over every hash carrying an "id" was the first version, and it read the
    # eight check names inside AUTOMATED_CSS_ANALYSIS's `config:` as eight rules
    # — so missing_metadata counted config keys that were never going to carry a
    # tier, and eight_px_rhythm, a check id, collided by case with the real
    # EIGHT_PX_RHYTHM. A rule's config is its own; only the populations are rules.
    def yaml_rules
      body = master_rules
      Master.flatten_rules(body.fetch("rules", {})).select { |r| r.is_a?(Hash) && r["id"] } +
        Array(body["learned_smells"]).select { |r| r.is_a?(Hash) && r["id"] }
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
    # the wording. A population that only restates it is the copy.
    #
    # There were four populations here. soul.yml was the fourth, and its rules
    # moved into law/practice.rb, so `absolute.rules` reads nil and the branch
    # contributed an empty list to every comparison — a reader of a key that no
    # longer exists, which reader_singularity counts and nothing else would.
    # A home is a population that DETECTS, and rules.yml mostly does not.
    #
    # This counted twenty on 2026-09-06 and one of them was a duplicate. The
    # other nineteen were the architecture: rules.yml is the catalogue, law/ and
    # the registry are the implementations, and an id necessarily appears in
    # both. Of the nineteen, thirteen carried `detect_semantic` — a question a
    # model answers about the same rule, which is that rule's model tier and not
    # a second definition of it. FAIL_VISIBLY is the shape: the catalogue
    # declares the prompt and law/universal.rb holds the lexical detector, with
    # the same source, the same severity and the same fix, word for word.
    # Counting that asked for one of the two to be deleted, and either deletion
    # loses a tier of a kernel rule. The rest carried `detect_structural`, whose
    # value names the structural detector that implements it — a pointer, not a
    # rival.
    #
    # So the question is narrower than "two homes": does one id have two things
    # that can fire? Measured after the change, that is zero — the twin campaign
    # this row was opened for is finished, and it stands as the guard against
    # regrowth. What the old count was hiding is in statement_conflicts below.
    #
    # `detect_lexical` in the catalogue does count: it is a deterministic
    # detector the YamlDeclarativeRule bridge runs. There are none today, which
    # is the escape hatch sitting idle rather than the check being blind.
    def detector_homes
      homes = Hash.new { |h, k| h[k] = [] }
      law_detectors.each { |id| homes[id] << "law/" }
      dsl_ids.map(&:upcase).each { |id| homes[id] << "RuleDSL" }
      yaml_rules.each do |r|
        next unless %w[detect_lexical].any? { |k| r[k].to_s.strip != "" }

        homes[r["id"].to_s.upcase] << "rules.yml"
      end
      homes
    end

    # A law with a `practice` or an `ask` cannot fire on a line: the first is a
    # rule about conduct and the second needs a model. FLAT_PIXELS is why this
    # matters — law/practice.rb states the flat-design principle and
    # surface_rules.rb detects `imageSmoothingEnabled = true`, which is the
    # principle and its one mechanical case, and law/practice.rb says so.
    def law_detectors
      loaded_laws.values.select(&:detect).map { |l| l.id.to_s.upcase }
    end

    def loaded_laws
      lib = File.join(MASTER, "lib")
      $LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
      require "master"
      require File.join(MASTER, "law", "law")
      ::Law.load_all(File.join(MASTER, "law")) if ::Law.rules.empty?
      ::Law.rules
    end

    def cross_population_duplicates
      detector_homes.select { |_, where| where.uniq.size > 1 }
                    .map { |id, where| { rule: id, homes: where.uniq } }
                    .sort_by { |h| h[:rule] }
    end

    # One id, two statements. This is what the old duplicate count was reaching
    # for and could not say: not that an id lives in two files, but that the two
    # tell a reader different things. Fourteen on 2026-09-06, eleven of them a
    # catalogue `fix` carrying an older draft of the instruction its own law
    # enforces — MEANINGFUL_NAMES said "Use domain-specific names" while the law
    # said "name it after what the right-hand side already calls it".
    #
    # Resolution, and it is the same rule the duplicates check has always
    # stated: whichever population holds the detector owns the wording, so a
    # drifted catalogue `fix` is rewritten to the law's. Severity is the
    # exception — the catalogue is the file that must carry tier and severity
    # for every rule, so the implementation follows it there.
    def statement_conflicts
      laws = loaded_laws
      registry_severity = dsl_severities
      yaml_rules.filter_map do |r|
        id = r["id"].to_s.upcase
        law = laws[id.to_sym]
        next conflict(id, "law/", law.fix, law.severity, r) if law

        severity = registry_severity[id]
        next unless severity

        conflict(id, "RuleDSL", r["fix"], severity, r)
      end
    end

    def conflict(id, home, fix, severity, entry)
      reasons = []
      reasons << "severity: #{normalised(entry["severity"])} declared, #{normalised(severity)} enforced" if
        normalised(severity) != normalised(entry["severity"])
      reasons << "fix" if fix.to_s.strip != entry["fix"].to_s.strip
      return nil if reasons.empty?

      { rule: id, home: home, reasons: reasons }
    end

    # law/ writes :warn where the catalogue writes "warning", and they are the
    # same severity.
    def normalised(severity) = severity.to_s.downcase.sub(/\Awarn\z/, "warning")

    def dsl_severities
      lib = File.join(MASTER, "lib")
      $LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
      require "master"
      require "review/scan/rule_dsl"
      Master::Review::Scan::Rule.registry.filter_map do |klass|
        rule = Master::Review::Scan::RuleFactory.build(klass, root: MASTER)
        [rule.id.to_s.upcase, rule.severity]
      rescue StandardError # scan: intentional — a rule that will not build has no severity to compare
        nil
      end.to_h
    end

    def ceilings
      master_rules # boots the runtime, so Master.law resolves
      Master.law("rule_ratchets", root: MASTER).fetch("hygiene")
    end

    def report
      { id_case_collisions: id_case_collisions,
        alias_shadows_live_rule: alias_shadows_live_rule,
        missing_metadata: missing_metadata,
        cross_population_duplicates: cross_population_duplicates,
        statement_conflicts: statement_conflicts }
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
      r[:statement_conflicts].each do |c|
        warn "rule_hygiene: #{c[:rule]} says one thing in rules.yml and another in #{c[:home]} (#{c[:reasons].join('; ')})"
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
