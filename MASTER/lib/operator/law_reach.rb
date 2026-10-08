# frozen_string_literal: true

# How many executable laws can fire, and under what conditions.
#
# The population is the live Law registry plus scanner-only LawDSL entries.
# Each executable law must expose at least one enforcement surface: a detector,
# a semantic question, or a practice hook. Policy data in data/laws.yml governs
# those laws but is not the executable population.
#
#   ruby MASTER/tools/law_reach.rb
#
# The semantic prompt drops info-severity violations deliberately — they double
# the token cost of every file for findings nobody acts on. Reach therefore
# measures the enforcement surface, not the severity policy.

require "set"
require "json"

module Operator
  module LawReach
    MASTER_DIR = File.expand_path("../..", __dir__)
    module_function

    # One inventory for the executable constitution and the scanner registry.
    # data/laws.yml is policy/configuration; it is not the executable rule list.
    def audit
      @audit ||= Master::Review::Scan::LawRegistryAudit.new(root: MASTER_DIR)
    end

    def rules
      @rules ||= audit.population
    end

    def mechanical(all)
      audit.mechanical(all)
    end

    def prompted(all)
      semantic_ids = executable_law_rules
        .select(&:enforceable?)
        .filter_map { |law| law.id.to_s if law.semantic? }
        .map(&:downcase).to_set
      Array(all).select { |row| semantic_ids.include?(row["id"].to_s.downcase) }
    end

    def practice(all)
      practice_ids = executable_law_rules
        .select(&:enforceable?)
        .filter_map { |law| law.id.to_s if law.practice }
        .map(&:downcase).to_set
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

    def ceiling
      Master.law("law_ratchets", root: MASTER_DIR).dig("reach", "unreachable")
    end

    def run(json: false)
      all = rules
      mech = mechanical(all)
      asked = prompted(all)
      conduct = practice(all)
      out = unreachable(all)
      limit = ceiling

      payload = {
        total: all.size,
        mechanical: mech.size,
        prompted: asked.size,
        practice: conduct.size,
        unreachable: out.map { |r| r["id"] },
        ceiling: limit
      }

      if json
        puts JSON.pretty_generate(payload)
        return out.size <= limit ? 0 : 1
      end

      puts "rule_reach: #{all.size} rules — #{mech.size} deterministic, #{asked.size} prompted, "            "#{conduct.size} practice, #{out.size} unreachable (ceiling #{limit})"
      out.each { |rule| puts "  #{rule["id"]}" }
      puts "rule_reach: every executable rule has a reachable enforcement surface" if out.empty?
      return 0 if out.size <= limit

      warn "rule_reach: #{out.size} executable law(s) have no detector, prompt, or practice surface; ceiling #{limit}"
      1
    end

    def executable_law_rules
      return @executable_law_rules if defined?(@executable_law_rules)

      $LOAD_PATH.unshift(File.join(MASTER_DIR, "lib")) unless $LOAD_PATH.include?(File.join(MASTER_DIR, "lib"))
      require "master"
      require File.join(MASTER_DIR, "law", "law")
      ::Law.load_all(File.join(MASTER_DIR, "law")) if ::Law.definitions.empty?
      @executable_law_rules = ::Law.definitions.values
    end
  end
end

if $PROGRAM_NAME == __FILE__
  exit Operator::LawReach.run(json: ARGV.include?("--json"))
end
