# frozen_string_literal: true

# Whether a rule's autofix promise reaches any code.
#
# `autofix:` in data/rules.yml carries three kinds of value and only one of them
# says anything a machine can act on: `false` is honest, a transform name is the
# useful form because it names the edit, and bare `true` claims a fix without
# saying how. Read the live split from `--json` rather than from a count here;
# the three numbers this header used to quote were stale within a fortnight.
#
# Two failures follow, and neither is visible from the field itself.
#
# dangling_transform: a rule naming a transform no code implements. It was seven
# of eight; efc96832f deleted those seven, all learned_smells entries whose
# `autofix:` nothing reads. A rule asking to be fixed by code that does not
# exist is a promise to a reader, and to any agent reading the rule to decide
# whether it may edit.
#
# bare_true: `true` claims a fix without naming it, so nothing can apply it and
# nothing can check it.
#
# Whether a rule can be FOUND is a separate question from whether its fix can be
# applied, and this tool got it wrong for as long as it asked it. It counted the
# three detect_* columns in rules.yml and reported twelve autofix claims as
# undetectable — every one of the twelve wrong. Ten have a live detector in law/
# or the RuleDSL registry, and the other two (WHITESPACE_PUNCTUATION,
# MESSAGE_CHAIN) carry `folded_into:` naming the rule that reports for them. It
# is the same instrument error tools/rule_reach.rb's own header records against
# itself, so the question is asked there now, once: `RuleReach.mechanical`
# already knows all three populations and loads the laws rather than grepping
# for them.
#
# Corrected, it reports six and none of them was on the old list:
# PRECOMPUTE_MATH, ANALOG_WARMTH, PURE_FUNCTIONS, SPECULATIVE_GENERALITY,
# SYSTEM_STATUS and CACHE_LLM each declare a semantic detector at info severity,
# which SemanticRule's info filter drops — so nothing ever reports them and the
# autofix claim can never be reached. Raise the severity, give one a detector,
# or say `autofix: false`.
#
# The target shape is `autofix: <transform>` or `autofix: false`. Bare true is
# the unfinished middle. Both counters are ceilings rather than errors because
# emptying them means either writing the transforms or demoting the rules — per
# rule, with a reason, not as a sweep.
#
#   ruby MASTER/tools/autofix_reach.rb
#   ruby MASTER/tools/autofix_reach.rb --json

require "yaml"
require "json"

module Pub4
  module AutofixReach
    MASTER = File.expand_path("..", __dir__)
    CEILING = File.join(MASTER, "data", "autofix_reach.yml")

    # Where a transform could plausibly live. Searched as whole words so a rule
    # naming `delete_phrase` is not satisfied by the substring in a comment.
    IMPLEMENTATION_GLOBS = ["lib/**/*.rb", "tools/*.rb"].freeze

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

    def rules
      found = []
      walk = lambda do |node|
        case node
        when Array then node.each(&walk)
        when Hash
          found << node if node["id"]
          node.each_value(&walk)
        end
      end
      walk.call(master_rules)
      found
    end

    # This file is excluded from its own corpus. The header above names all seven
    # missing transforms in order to explain them, which satisfied the search and
    # made the check report every transform implemented — a tool whose
    # documentation is the evidence it looks for.
    def implemented?(name)
      @sources ||= IMPLEMENTATION_GLOBS.flat_map { |g| Dir.glob(File.join(MASTER, g)) }
                                       .reject { |f| f.include?("/vendor/") || f == File.expand_path(__FILE__) }
                                       .map { |f| File.read(f, encoding: "UTF-8").scrub }
                                       .join("\n")
      @sources.match?(/(?:^|[^\w.])#{Regexp.escape(name)}\b/)
    end

    # A rule naming a transform is the one that mentions it; that mention must
    # not count as its implementation.
    def named_transforms
      rules.filter_map do |r|
        value = r["autofix"]
        next if [true, false, nil].include?(value)

        { rule: r["id"], transform: value.to_s }
      end
    end

    def dangling = named_transforms.reject { |n| implemented?(n[:transform]) }

    # Detection is RuleReach's question, not this tool's: it knows law/, the
    # RuleDSL registry and `folded_into` as well as the yml columns, and it
    # loads the laws instead of grepping for a literal `Law.define(:ID)`.
    def detectable_ids
      @detectable_ids ||= begin
        require File.join(MASTER, "tools/rule_reach")
        all = RuleReach.rules
        (RuleReach.mechanical(all) + RuleReach.prompted(all)).map { |r| r["id"].to_s }.to_set
      end
    end

    def bare_true
      rules.select { |r| r["autofix"] == true }.map do |r|
        { rule: r["id"], detected: detectable_ids.include?(r["id"].to_s) }
      end
    end

    def ceilings = YAML.safe_load_file(CEILING)

    def report
      { dangling: dangling, bare_true: bare_true, named: named_transforms.size }
    end

    def run(json: false)
      found = report
      return (puts JSON.pretty_generate(found)) || found[:dangling].empty? if json

      puts "autofix_reach: #{found[:named]} rule(s) name a transform, #{found[:bare_true].size} say only `true`"

      if found[:dangling].empty?
        puts "autofix_reach: every named transform is implemented"
      else
        found[:dangling].each do |d|
          warn "autofix_reach: #{d[:rule]} names transform `#{d[:transform]}`, which is implemented nowhere"
        end
      end

      undetectable = found[:bare_true].reject { |b| b[:detected] }
      unless undetectable.empty?
        warn "autofix_reach: #{undetectable.size} rule(s) claim autofix and nothing reports them — " \
             "no detector in rules.yml, law/ or the registry, or a semantic-only detector the info " \
             "filter drops: #{undetectable.map { |b| b[:rule] }.join(', ')}"
      end

      c = ceilings
      over = []
      over << "dangling #{found[:dangling].size} > #{c['dangling']}" if found[:dangling].size > c["dangling"]
      over << "bare_true #{found[:bare_true].size} > #{c['bare_true']}" if found[:bare_true].size > c["bare_true"]
      over.each { |line| warn "autofix_reach: exceeds baseline — #{line}" }
      over.empty?
    end
  end
end

if $PROGRAM_NAME == __FILE__
  ok = Pub4::AutofixReach.run(json: ARGV.include?("--json"))
  exit(ok ? 0 : 1)
end
