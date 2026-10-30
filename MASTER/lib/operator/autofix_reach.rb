# frozen_string_literal: true

# Whether a Law's autofix promise reaches any code.
#
# `autofix:` in data/laws.yml carries three kinds of value and only one of them
# says anything a machine can act on: `false` is honest, a transform name is the
# useful form because it names the edit, and bare `true` claims a fix without
# saying how. Read the live split from `--json`, not from a count in prose.
#
# dangling_transform: a Law naming a transform no code implements, a promise to
# any agent reading the Law to decide whether it may edit.
#
# bare_true: `true` claims a fix without naming it, so nothing can apply it and
# nothing can check it. A bare-true Law nothing reports is listed separately:
# whether a Law can be found is LawReach.mechanical's question (the one
# ::Law.define population and `folded_into:`), and a semantic detector at info severity
# is dropped by SemanticLaw's info filter, so its autofix claim is unreachable.
# Raise the severity, give it a detector, or say `autofix: false`.
#
# The target shape is `autofix: <transform>` or `autofix: false`. Both counters
# are ceilings rather than errors because emptying them means writing the
# transforms or demoting the Laws, per Law with a reason, not as a sweep.
#
#   ruby MASTER/tools/autofix_reach.rb
#   ruby MASTER/tools/autofix_reach.rb --json

require "yaml"
require "json"

module Operator
  module AutofixReach
    MASTER = File.expand_path("../..", __dir__)
    CEILING = File.join(MASTER, "data", "autofix_reach.yml")

    # Where a transform could plausibly live. Searched as whole words so a Law
    # naming `delete_phrase` is not satisfied by the substring in a comment.
    IMPLEMENTATION_GLOBS = ["lib/**/*.rb", "tools/*.rb"].freeze

    module_function

    # Through the accessor, not a second load of laws.yml: the file this tool
    # audits has to be the file the runtime reads, and reader_singularity is
    # the ratchet that keeps those two from drifting apart.
    def master_laws
      lib = File.join(MASTER, "lib")
      $LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
      require "master"
      Master.load_laws(root: MASTER)
    end

    def laws
      found = []
      walk = lambda do |node|
        case node
        when Array then node.each(&walk)
        when Hash
          found << node if node["id"]
          node.each_value(&walk)
        end
      end
      walk.call(master_laws)
      found
    end

    # This file is excluded from its own corpus: a transform it names while
    # explaining one would otherwise count as that transform's implementation.
    def implemented?(name)
      @sources ||= IMPLEMENTATION_GLOBS.flat_map { |g| Dir.glob(File.join(MASTER, g)) }
                                       .reject { |f| f.include?("/vendor/") || f == File.expand_path(__FILE__) }
                                       .map { |f| File.read(f, encoding: "UTF-8").scrub }
                                       .join("\n")
      @sources.match?(/(?:^|[^\w.])#{Regexp.escape(name)}\b/)
    end

    # A Law naming a transform is the one that mentions it; that mention must
    # not count as its implementation.
    def named_transforms
      laws.filter_map do |r|
        value = r["autofix"]
        next if [true, false, nil].include?(value)

        { Law: r["id"], transform: value.to_s }
      end
    end

    def dangling = named_transforms.reject { |n| implemented?(n[:transform]) }

    # Detection is LawReach's question, not this tool's: it knows the
    # ::Law.define population and `folded_into` as well as the yml columns, and it
    # loads the laws instead of grepping for a literal `Law.define(:ID)`.
    def detectable_ids
      @detectable_ids ||= begin
        require File.join(MASTER, "lib/operator/law_reach")
        all = LawReach.laws
        (LawReach.mechanical(all) + LawReach.prompted(all)).map { |r| r["id"].to_s }.to_set
      end
    end

    def bare_true
      laws.select { |r| r["autofix"] == true }.map do |r|
        { Law: r["id"], detected: detectable_ids.include?(r["id"].to_s) }
      end
    end

    def ceilings = YAML.safe_load_file(CEILING)

    def report
      { dangling:, bare_true:, named: named_transforms.size }
    end

    def run(json: false)
      found = report
      return (puts JSON.pretty_generate(found)) || found[:dangling].empty? if json

      print_findings(found)
      warn_ceilings(found)
    end

    def print_findings(found)
      puts "autofix_reach: #{found[:named]} Law(s) name a transform, #{found[:bare_true].size} say only `true`"

      if found[:dangling].empty?
        puts "autofix_reach: every named transform is implemented"
      else
        found[:dangling].each do |d|
          warn "autofix_reach: #{d[:Law]} names transform `#{d[:transform]}`, which is implemented nowhere"
        end
      end

      undetectable = found[:bare_true].reject { |b| b[:detected] }
      return if undetectable.empty?

      warn "autofix_reach: #{undetectable.size} Law(s) claim autofix and nothing reports them — " \
           "no detector in laws.yml, law/ or the registry, or a semantic-only detector the info " \
           "filter drops: #{undetectable.map { |b| b[:Law] }.join(', ')}"
    end

    def warn_ceilings(found)
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
  ok = Operator::AutofixReach.run(json: ARGV.include?("--json"))
  exit(ok ? 0 : 1)
end
