# frozen_string_literal: true

require "yaml"

# Load enforcement modules
require_relative "enforcement/layers"
require_relative "enforcement/scopes"

module MASTER
  # Enforcement - 6-layer axiom enforcement at 4 scopes
  # Layers: Literal → Lexical → Conceptual → Semantic → Cognitive → Language Axiom
  # Scopes: Line → Unit → File → Framework
  module Enforcement
    extend self
    extend Layers
    extend Scopes

    LAYERS = %i[literal lexical conceptual semantic cognitive language_axiom].freeze
    SCOPES = %i[line unit file framework].freeze
    SMELLS_FILE = File.join(__dir__, "..", "data", "smells.yml")

    # Simulated execution scenarios for safety pre-checks
    # SECURITY NOTE: simulate_with_input() evaluates arbitrary code in a controlled binding.
    # This is intentional for pre-execution safety validation. Code must be trusted.
    # For production use, consider subprocess execution with timeouts.
    SIMULATED_SCENARIOS = [
      {
        scenario: "empty_input",
        cases: [nil, "", [], 0, false]
      },
      {
        scenario: "boundary_values",
        cases: [
          2**63 - 1,  # max int
          "x" * 10_000,  # very long string
          "\u{1F600}",  # unicode emoji
          Float::INFINITY
        ]
      },
      {
        scenario: "malformed_input",
        cases: [
          "{ invalid json",
          "SELECT * FROM users; DROP TABLE users;",
          "<script>alert('xss')</script>",
          "../../../etc/passwd"
        ]
      }
    ].freeze

    @smells_mutex = Mutex.new

    class << self
      def smells
        @smells_mutex.synchronize do
          @smells ||= File.exist?(SMELLS_FILE) ? YAML.safe_load_file(SMELLS_FILE) : {}
        end
      end

      def thresholds
        smells["thresholds"] || {}
      end

      # Full analysis: all layers, all scopes
      def analyze(code, axioms: nil, filename: "code")
        axioms ||= DB.axioms
        {
          filename: filename,
          line: check_lines(code, filename),
          unit: check_units(code, filename),
          file: check(code, axioms: axioms, filename: filename),
        }
      end

      # Analyze entire framework (multiple files)
      def analyze_framework(files, axioms: nil)
        axioms ||= DB.axioms
        file_results = files.map { |f, content| analyze(content, axioms: axioms, filename: f) }
        framework_violations = check_framework(files, axioms)

        {
          files: file_results,
          framework: framework_violations,
          summary: {
            total_violations: file_results.sum { |r| r[:file][:violations].size } + framework_violations.size,
            files_checked: files.size,
            layers: LAYERS,
            scopes: SCOPES,
          },
        }
      end

      # Run all 6 layers on single file
      def check(code, axioms: nil, filename: "code")
        axioms ||= DB.axioms
        violations = []

        LAYERS.each do |layer|
          layer_violations = send(:"check_#{layer}", code, axioms, filename)
          violations.concat(layer_violations)
        end

        { filename: filename, violations: violations, layers_checked: LAYERS }
      end

      # Suggest better names from smells.yml
      def suggest(word, type: :verb)
        suggestions = smells.dig(type == :verb ? "generic_verbs" : "vague_nouns", word)
        suggestions || []
      end

      # Simulate code execution with test scenarios for safety validation
      # SECURITY NOTE: This evaluates code. Use only on trusted code or in sandboxed environments.
      def simulate_execution(code)
        results = []

        SIMULATED_SCENARIOS.each do |scenario|
          scenario[:cases].each do |test_input|
            result = simulate_with_input(code, test_input)
            results << {
              scenario: scenario[:scenario],
              input: test_input.inspect[0..50],
              success: result != :error,
            }
          end
        end

        results
      end

      private

      # SECURITY NOTE: This uses eval() to execute code in a controlled binding.
      # The code parameter must be trusted. For untrusted code, use RubyVM::InstructionSequence.compile
      # for syntax-only validation, or execute in a subprocess with timeout.
      def simulate_with_input(code, input)
        binding_obj = binding
        binding_obj.local_variable_set(:input, input)
        eval(code, binding_obj)
      rescue StandardError
        :error
      end
    end
  end
end
