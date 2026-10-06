# frozen_string_literal: true

# How many rules can fire, and under what conditions.
#
# A rule in data/laws.yml reaches code three ways: a lexical detector, a
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

require "set"
require "json"

module Operator
  module RuleReach
    MASTER_DIR = File.expand_path("../..", __dir__)
    LAW_ROOT = File.join(MASTER_DIR, "law")

    module_function

    # One inventory for the executable constitution and the scanner registry.
    # data/laws.yml is policy/configuration; it is not the executable rule list.
    def rules
      @rules ||= executable_law_rows + registry_rows
    end

    def executable_law_rows
      load_laws unless defined?(::Law) && !::Law.rules.empty?
      ::Law.rules.values.map do |law|
        {
          "id" => law.id.to_s,
          "severity" => law.severity.to_s,
          "mode" => law.mode.to_s,
          "languages" => Array(law.languages).map(&:to_s),
          "lifecycle" => law.lifecycle.to_s,
          "autofix" => law.autofix.to_s,
          "detect" => !law.detect.nil?,
          "semantic" => !law.ask.nil?,
          "practice" => !law.practice.nil?
        }
      end
    end

    def registry_rows
      require File.join(MASTER_DIR, "lib", "review", "scan", "infra_helpers")
      scanner = Master::Review::Scan::InfraHelpers.build_scanner(root: MASTER_DIR, agent: nil)
      audit = Master::Review::Scan::RuleRegistryAudit.new(root: MASTER_DIR)
      executable_ids = ::Law.rules.keys.map { |id| id.to_s.downcase }.to_set

      scanner.rules.filter_map do |rule|
        next unless audit.shipped?(rule.class)
        id = rule.id.to_s
        next if executable_ids.include?(id.downcase)

        {
          "id" => id,
          "severity" => (rule.respond_to?(:severity) ? rule.severity : :warning).to_s,
          "mode" => "scanner",
          "languages" => (rule.respond_to?(:languages) ? Array(rule.languages) : []).map(&:to_s),
          "lifecycle" => "active",
          "autofix" => (rule.respond_to?(:autofix) ? rule.autofix : false).to_s,
          "detect" => true,
          "semantic" => false,
          "practice" => false
        }
      end
    end

    def load_laws
      $LOAD_PATH.unshift(File.join(MASTER_DIR, "lib")) unless $LOAD_PATH.include?(File.join(MASTER_DIR, "lib"))
      require "master"
      require File.join(MASTER_DIR, "law", "law")
      ::Law.load_all(LAW_ROOT) if ::Law.rules.empty?
      ::Law.rules
    end

    # A rule is mechanical when a deterministic executable law or shipped
    # scanner rule can report it. A semantic law is prompted. A practice-only
    # law is still reachable governance; it is not a source detector and must
    # not be misreported as an unreachable law.
    def mechanical(all)
      detector_ids = executable_law_rows.filter_map { |row| row["id"] if row["detect"] }
      detector_ids.concat(registry_rows.map { |row| row["id"] })
      folded = Array(all).filter_map { |row| row["folded_into"].to_s if row.is_a?(Hash) && row["folded_into"] }
      ids = (detector_ids + folded).map(&:downcase).to_set

      Array(all).select { |row| ids.include?(row["id"].to_s.downcase) }
    end

    def prompted(all)
      semantic_ids = executable_law_rows.filter_map { |row| row["id"] if row["semantic"] }.map(&:downcase).to_set
      Array(all).select { |row| semantic_ids.include?(row["id"].to_s.downcase) }
    end

    def practice(all)
      practice_ids = executable_law_rows.filter_map { |row| row["id"] if row["practice"] }.map(&:downcase).to_set
      Array(all).select { |row| practice_ids.include?(row["id"].to_s.downcase) }
    end

    def unreachable(all = rules)
      mechanical_ids = mechanical(all).map { |row| row["id"].to_s.downcase }.to_set
      prompted_ids = prompted(all).map { |row| row["id"].to_s.downcase }.to_set
      practice_ids = practice(all).map { |row| row["id"].to_s.downcase }.to_set
      Array(all).reject do |row|
        id = row["id"].to_s.downcase
        mechanical_ids.include?(id) || prompted_ids.include?(id) || practice_ids.include?(id)
      end
    end

    def run(ratchet: false, json: false)
      all = rules
      mech = mechanical(all)
      asked = prompted(all)
      conduct = practice(all)
      out = unreachable(all)

      payload = {
        total: all.size,
        mechanical: mech.size,
        prompted: asked.size,
        practice: conduct.size,
        unreachable: out.map { |r| r["id"] }
      }

      if json
        puts JSON.pretty_generate(payload)
        return out.empty? ? 0 : 1
      end

      puts "rule_reach: #{all.size} rules — #{mech.size} deterministic, #{asked.size} prompted, "            "#{conduct.size} practice, #{out.size} unreachable"
      out.each { |rule| puts "  #{rule["id"]}" }
      puts "rule_reach: every executable rule has a reachable enforcement surface" if out.empty?
      return 0 if out.empty?

      warn "rule_reach: an executable law has no detector, prompt, or practice surface"
      1
    end
  end
end

if $PROGRAM_NAME == __FILE__
  exit Operator::RuleReach.run(json: ARGV.include?("--json"))
end
