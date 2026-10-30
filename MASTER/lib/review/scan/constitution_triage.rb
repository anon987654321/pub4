# frozen_string_literal: true

module Master
  module Review
    module Scan
      # Sorts a deep scan's findings into the four things they actually are, so
      # `rake constitution` reports a number an operator can act on rather than
      # one dominated by the scanner reading itself.
      #
      # Its consumer is the Rakefile (`rake constitution`, part of `rake audit`),
      # not lib/, so a dead-file census over lib/ alone reads it as unused.
      # test_constitution_triage.rb fails when an id in RULE_RETUNE_IDS stops
      # naming a rule, which is what EXEMPTIONS_EXPIRE asks of an allowlist.
      class ConstitutionTriage
        # law/ holds the Law definitions and their detectors, each of which
        # carries the pattern it forbids.
        SCANNER_SELF_PATHS = %r{
          \Alaw/|
          \Alib/review/scan/(?:rules/|rule|law_tree|detector|canonical_law_adapter|scanner|file_processor|self_scan|self_test|
            infra_helpers|law_registry_audit)
        }x

        # Laws under active retune: noisy enough that gating on them would check
        # on the detector rather than on the code. Every id here must name a law
        # the scanner, data/laws.yml or law/ still defines. A detector fault is
        # fixed in the detector, not parked here: parking stops anyone measuring it.
        RULE_RETUNE_IDS = %w[
          COMPLETION_THEATER
          CONSECUTIVE_BLANK_LINES
          COUPLER_SMELLS
          CQS
          CYCLOMATIC_COMPLEXITY
          DEAD_CODE
          DEBUG_OUTPUT
          EXPLICIT
          FEATURE_ENVY
          FEW_ARGUMENTS
          FINAL_NEWLINE
          LAW_OF_DEMETER
          LAZY_CLASS
          LONG_LINE
          LONG_PARAMETER_LIST
          MAGIC_COLOR
          MEANINGFUL_NAMES
          NO_ABBREVIATED_IDENTIFIERS
          NO_COLUMN_ALIGN
          NO_MULTIPLE_LANGUAGES
          PARAMETERIZED_SLUG
          PATTERN_EXTRACTION
          PERCENT_LITERAL
          RESCUE_ON_DEF
          RUBY_NUMERIC_UNDERSCORE
          RUBY_SYMBOL_TO_PROC
          RUBY_TERNARY_NOT_NESTED
          SIMULATION
          SINGLE_PRIVATE_SECTION
          SMALL_FILES
          SMALL_FUNCTIONS
          TRAILING_COMMAS
          TRAILING_COMMENT
          TRANSFORM_KEYS
          TYPOGRAPHIC_EXCELLENCE
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
          return :timed_out if finding[:law].to_s == "SCAN_TIMEOUT"

          rel = relative_path(finding[:file].to_s)
          return :scanner_self_reference if rel.match?(SCANNER_SELF_PATHS)
          return :rule_retune if RULE_RETUNE_IDS.include?(finding[:law].to_s)

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
