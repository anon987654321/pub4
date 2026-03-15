# frozen_string_literal: true

require "yaml"

module Master
  module Scan
    module Rules
      # AxiomCoverageRule — meta-level rule. Checks that every axiom in axioms.yml
      # has at least one scan rule referencing it, and that all @axiom_tags in scan
      # rules correspond to real axioms. Violations mean the axiom system has gaps.
      #
      # This is the meta-check: the enforcement system enforcing itself.
      class AxiomCoverageRule < Rule
        def initialize(root: nil)
          super()
          @root        = root
          @id          = "axiom_coverage"
          @description = "Every axiom must have scan rule coverage; every tag must be a real axiom"
          @severity    = :warning
          @axiom_tags  = []
        end

        def check(code, path:)
          # Only run when scanning the scan rules directory itself.
          return [] unless path.include?("scan/rules") || path.include?("scan/rule.rb")
          return [] unless @root

          axiom_ids  = load_axiom_ids
          tagged_ids = load_tagged_ids
          findings   = []

          # Orphaned tags: in code but not in axioms.yml
          (tagged_ids - axiom_ids).each do |id|
            findings << finding(line: 1, message: "axiom_tag :#{id} has no entry in axioms.yml — define it or remove the tag")
          end

          # Uncovered axioms: in axioms.yml but no scan rule covers them
          (axiom_ids - tagged_ids).each do |id|
            findings << finding(line: 1, message: "axiom #{id} has no scan rule coverage — add a rule or accept as advisory")
          end

          findings
        end

        private

        def load_axiom_ids
          path = File.join(@root, "data", "axioms.yml")
          return [] unless File.exist?(path)

          data = YAML.safe_load_file(path)
          ids  = []
          ids += data.dig("kernel")&.keys || []
          ids += (data.dig("philosophy", "prioritized_top_25") || []).map { |a| a["id"] }
          ids.map(&:to_s).uniq
        rescue StandardError
          []
        end

        def load_tagged_ids
          rules_dir = File.join(@root, "lib", "master", "scan", "rules")
          return [] unless Dir.exist?(rules_dir)

          Dir.glob(File.join(rules_dir, "*.rb")).flat_map { |f|
            File.read(f).scan(/:([A-Z_]{3,})/).flatten
          }.uniq
        rescue StandardError
          []
        end
      end
    end
  end
end
