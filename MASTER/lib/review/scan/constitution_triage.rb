# frozen_string_literal: true

module Master
  module Review
    module Scan
      # Sorts a deep scan's findings into the four things they actually are, so
      # `rake constitution` reports a number an operator can act on rather than
      # one dominated by the scanner reading itself.
      #
      # This class was deleted on 2026-08-28 as having no consumer. It had one:
      # the Rakefile requires it and calls it four times, and `rake constitution`
      # is the second task in `rake audit`, so the deletion took the whole audit
      # down with it — `bin/check --profile=full` included. The dead-file census
      # behind it searched for the constant in lib/ and never looked at a
      # Rakefile, which is the instrument failure VERIFY_THE_INSTRUMENT names.
      #
      # The objection that commit raised was right, and is answered below rather
      # than restored with the class: RULE_RETUNE_IDS was fifty rule ids copied
      # by hand out of data/rules.yml with nothing asserting the two still agree.
      # Eight named no live rule in any of the three registries — five of them
      # the lowercase spelling of a rule since renamed (debug_output, long_line,
      # god_class, prose_active_voice, prose_omit_qualifiers) — and message_chain
      # is `folded_into: LAW_OF_DEMETER` with `detect_lexical: ~`, so it has no
      # detector to be noisy with and Demeter already stands in this list.
      #
      # All eight are gone, and test_constitution_triage.rb fails when an id here
      # stops naming a rule, which is what EXEMPTIONS_EXPIRE asks of an allowlist.
      class ConstitutionTriage
        SCANNER_SELF_PATHS = %r{\Alib/review/scan/(?:rules/|rule|rule_dsl|rule_factory|scanner|file_processor|self_scan|self_test|infra_helpers|rule_registry_audit)}.freeze

        # Rules under active retune: noisy enough that gating on them would gate
        # on the detector rather than on the code. Every id here must name a rule
        # the scanner, data/rules.yml or law/ still defines.
        RULE_RETUNE_IDS = %w[
          COMPLETION_THEATER
          CONSECUTIVE_BLANK_LINES
          COUPLER_SMELLS
          CQS
          CYCLOMATIC_COMPLEXITY
          DEAD_CODE
          DEBUG_OUTPUT
          DOUBLE_QUOTES_RUBY
          EXPLICIT
          FEATURE_ENVY
          FEW_ARGUMENTS
          FILE_LAYOUT
          FINAL_NEWLINE
          KEYWORD_ARGS
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
          duplicate_code
          future_tense
          magic_number
          sycophancy
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
