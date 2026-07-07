# frozen_string_literal: true

module Master
  module Judge
    module Scan
      class ConstitutionTriage
        SCANNER_SELF_PATHS = %r{\Alib/judge/scan/(?:rules/|rule|rule_dsl|rule_factory|scanner|file_processor|self_scan|self_test|infra_helpers|rule_registry_audit)}.freeze
        RULE_RETUNE_IDS = %w[
          DEAD_CODE
          FILE_LAYOUT
          LONG_LINE
          MEANINGFUL_NAMES
          NO_ABBREVIATED_IDENTIFIERS
          NO_COLUMN_ALIGN
          TRAILING_COMMAS
          COUPLER_SMELLS
          DOUBLE_QUOTES_RUBY
          debug_output
          god_class
          long_line
          magic_number
          message_chain
          veto_patterns
        ].freeze

        Bucket = Data.define(:name, :findings)

        def initialize(root:)
          @root = File.expand_path(root)
        end

        def buckets(findings)
          grouped = findings.group_by { |finding| classify(finding) }
          %i[true_violation scanner_self_reference timed_out rule_retune].map do |name|
            Bucket.new(name:, findings: grouped.fetch(name, []))
          end
        end

        def actionable_count(findings)
          buckets(findings).select { |bucket| bucket.name == :true_violation }.sum { |bucket| bucket.findings.size }
        end

        private

        def classify(finding)
          return :timed_out if finding[:rule].to_s == "SCAN_TIMEOUT"

          rel = relative_path(finding[:file].to_s)
          return :scanner_self_reference if rel.match?(SCANNER_SELF_PATHS)
          return :rule_retune if RULE_RETUNE_IDS.include?(finding[:rule].to_s)

          :true_violation
        end

        def relative_path(path)
          expanded = File.expand_path(path)
          return path unless expanded.start_with?("#{@root}/")

          expanded.delete_prefix("#{@root}/")
        end
      end
    end
  end
end
