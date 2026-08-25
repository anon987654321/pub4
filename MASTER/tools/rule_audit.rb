# frozen_string_literal: true

# Audits the rules, not the code they judge.
#
# Every other instrument here asks whether the tree obeys the rules. This asks
# whether a rule can see its own subject, because on 2026-08-25 three could not
# and nothing said so for as long as they had existed:
#
#   FROZEN_STRING_LITERAL asks whether a file opens with the magic comment.
#   considered_text blanks comment lines before a detector reads them, so it
#   fired on 423 of 423 files under MASTER/lib that carry the comment.
#   SQUINT_TEST looks for four consecutive newlines, and a blanked comment line
#   IS a newline, so every heavily-commented file was a finding about blank
#   lines it does not have.
#
# Both passed prove! at every boot. That is the whole finding, and it is why the
# first check below exists rather than a cleverer one: a fixture proves with
# file "-", which has no extension and therefore no comment syntax, so the
# fixture is read whole while the real file is not. The proof and the production
# path disagreed about what the detector would be shown, and a rule cannot
# notice that about itself.
#
# Three deterministic checks, no model required:
#
#   fixture_blindness  Re-prove bad/good through a filename carrying a real
#                      extension for the rule's language. A rule whose verdict
#                      changes was proved against input its subjects never get.
#   saturation         Firing rate over a real corpus. A rule that flags most of
#                      what it reads is not enforcing a rule, it is describing
#                      the codebase, and its findings are noise at scale.
#   silent             Fires on nothing in the corpus. Either the tree obeys it
#                      or it is aimed at something that is not there — the
#                      distinction needs a person, so this reports and does not
#                      fail.
#
#   ruby MASTER/tools/rule_audit.rb
#   ruby MASTER/tools/rule_audit.rb --json
#
# The adversarial half — steelman the rule, then ask what it fires on that it
# should not — belongs on top of this, not instead of it. These three are free,
# repeatable, and caught every one of the three real bugs.

require "json"

module Pub4
  module RuleAudit
    MASTER = File.expand_path("..", __dir__)
    ROOT = File.expand_path("..", MASTER)

    # Enough real files to make a rate meaningful, few enough to stay quick.
    # MASTER/lib is the densest Ruby in the tree and the corpus the 423/423
    # measurement came from; the others keep a ruby-only rule from being judged
    # on ruby alone.
    CORPUS = [
      "MASTER/lib/**/*.rb",
      "MASTER/law/*.rb",
      "RAILS/shared/app/**/*.rb",
      "RAILS/shared/app/assets/stylesheets/*.scss",
      "RAILS/shared/frontend/*.js"
    ].freeze

    # A rule flagging more than this share of the files it applies to is
    # reporting a property of the codebase rather than a violation. Set where it
    # is because the three real defects sat at 100% and the highest legitimate
    # rate measured was well under half.
    SATURATION = 0.5

    module_function

    def law
      unless defined?(::Law)
        require File.join(MASTER, "lib", "master")
        require File.join(MASTER, "law", "law")
      end
      ::Law.load_all(File.join(MASTER, "law")) if ::Law.rules.empty?
      ::Law.rules
    end

    def corpus
      @corpus ||= CORPUS.flat_map { |glob| Dir.glob(File.join(ROOT, glob)) }
                        .reject { |f| f.include?("/vendor/") || f.include?("/node_modules/") }
                        .sort
    end

    # Symbol, because that is what production passes. LawBridgeRule#check does
    # `language(path)&.to_sym` and applies? compares against `languages`, which
    # a law declares as %i[ruby]. Handing it the map's String made applies?
    # false for every language-scoped rule, so the first version of this file
    # measured 0 findings and reported the tree clean — an auditor with exactly
    # the defect it was written to find.
    def language_of(path) = Master::FILE_LANGUAGE_MAP[File.extname(path)]&.to_sym

    # An extension the rule's own `languages` would accept. Rules that declare
    # none apply everywhere, so ruby stands in for them.
    def realistic_extension(rule)
      wanted = rule.languages.map(&:to_s)
      wanted = ["ruby"] if wanted.empty?
      Master::FILE_LANGUAGE_MAP.find { |_, lang| wanted.include?(lang) }&.first || ".rb"
    end

    # The check that would have caught all three. Prove the fixtures the way a
    # real file is read, not the way a fixture is.
    def fixture_blindness(rule)
      ext = realistic_extension(rule)
      as_file = "fixture#{ext}"
      bad_seen = !rule.scan(rule.bad, file: as_file).empty?
      good_seen = rule.scan(rule.good, file: as_file).empty?
      return nil if bad_seen && good_seen

      reason = []
      reason << "bad fixture no longer flagged" unless bad_seen
      reason << "good fixture now flagged" unless good_seen
      { rule: rule.id.to_s, extension: ext, detail: reason.join(" and ") }
    end

    def rates
      files = corpus.map { |path| [path, language_of(path), File.read(path, encoding: "UTF-8").scrub] }
      law.values.select(&:scannable?).filter_map do |rule|
        applicable = files.select { |path, lang, _| rule.applies?(path, lang) }
        next if applicable.empty?

        hits = applicable.count { |path, _, text| !rule.scan(text, file: path).empty? }
        { rule: rule.id.to_s, hits:, applicable: applicable.size, rate: hits.fdiv(applicable.size) }
      end
    end

    # "Which rules are never asked" belongs to tools/rule_reach.rb, which counts
    # 57 and had counted them before this file existed. A version of it here
    # measured 67 by also counting rules whose semantic prompt is dropped while a
    # lexical detector still enforces them — reachable rules, reported as gaps.
    # One question, one instrument; this one is about whether a rule that DOES
    # run can see its subject.
    def audit
      blind = law.values.select(&:scannable?).filter_map { |rule| fixture_blindness(rule) }
      measured = rates
      {
        rules: law.size,
        lexical: law.values.count(&:scannable?),
        semantic: law.values.count(&:semantic?),
        practice: law.values.count { |r| !r.practice.nil? },
        corpus: corpus.size,
        fixture_blindness: blind,
        saturation: measured.select { |r| r[:rate] > SATURATION }.sort_by { |r| -r[:rate] },
        silent: measured.select { |r| r[:hits].zero? }.map { |r| r[:rule] }.sort
      }
    end

    def run(json: false)
      result = audit
      return (puts JSON.pretty_generate(result)) || result[:fixture_blindness].empty? if json

      puts "rule_audit: #{result[:lexical]} with a detector + #{result[:semantic]} asked + #{result[:practice]} practice, over #{result[:corpus]} files"

      if result[:fixture_blindness].empty?
        puts "rule_audit: every fixture survives being read as a real file"
      else
        result[:fixture_blindness].each do |f|
          warn "rule_audit: #{f[:rule]} proves on \"-\" but not on #{f[:extension]} — #{f[:detail]}"
        end
        warn "rule_audit: a fixture read whole and a file read with its comments blanked are different inputs"
      end

      result[:saturation].each do |r|
        warn format("rule_audit: %s fires on %d of %d applicable files (%d%%) — describing the tree, not judging it",
                    r[:rule], r[:hits], r[:applicable], (r[:rate] * 100).round)
      end

      puts "rule_audit: #{result[:silent].size} rule(s) fired on nothing here — #{result[:silent].join(', ')}" unless result[:silent].empty?


      result[:fixture_blindness].empty? && result[:saturation].empty?
    end
  end
end

if $PROGRAM_NAME == __FILE__
  ok = Pub4::RuleAudit.run(json: ARGV.include?("--json"))
  exit(ok ? 0 : 1)
end
