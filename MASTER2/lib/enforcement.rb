# frozen_string_literal: true

require "yaml"

# Load enforcement modules
require_relative "enforcement/layers"
require_relative "enforcement/scopes"

module MASTER
  # QualityStandards - Unified quality thresholds from quality_thresholds.yml
  module QualityStandards
    extend self

    THRESHOLDS_FILE = File.join(__dir__, "..", "data", "quality_thresholds.yml")

    def thresholds
      @thresholds ||= begin
        return defaults unless File.exist?(THRESHOLDS_FILE)
        YAML.safe_load_file(THRESHOLDS_FILE, symbolize_names: true) || defaults
      end
    end

    def defaults
      {
        file_lines: { warn: 250, error: 300, self_test_max: 300 },
        method_lines: { warn: 15, error: 25 },
        max_self_test_issues: 0,
        max_self_test_violations: 0
      }
    end

    def max_file_lines
      thresholds.dig(:file_lines, :error) || 300
    end

    def max_file_lines_warn
      thresholds.dig(:file_lines, :warn) || 250
    end

    def max_file_lines_self_test
      thresholds.dig(:file_lines, :self_test_max) || 300
    end

    def max_method_lines
      thresholds.dig(:method_lines, :error) || 25
    end

    def max_method_lines_warn
      thresholds.dig(:method_lines, :warn) || 15
    end

    def max_self_test_issues
      thresholds[:max_self_test_issues] || 0
    end

    def max_self_test_violations
      thresholds[:max_self_test_violations] || 0
    end
  end

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

  # LanguageAxioms - Language-specific beauty rules
  # 78 axioms across Ruby, Rails, Zsh, HTML/ERB, CSS/SCSS, JavaScript, and universal
  module LanguageAxioms
    AXIOMS_FILE = File.join(__dir__, "..", "data", "language_axioms.yml")

    EXTENSION_MAP = {
      ".rb"    => %w[ruby rails universal],
      ".rake"  => %w[ruby rails universal],
      ".gemspec" => %w[ruby universal],
      ".sh"    => %w[zsh universal],
      ".zsh"   => %w[zsh universal],
      ".bash"  => %w[zsh universal],
      ".html"  => %w[html_erb universal],
      ".erb"   => %w[html_erb universal],
      ".htm"   => %w[html_erb universal],
      ".css"   => %w[css_scss universal],
      ".scss"  => %w[css_scss universal],
      ".sass"  => %w[css_scss universal],
      ".js"    => %w[javascript universal],
      ".mjs"   => %w[javascript universal],
      ".jsx"   => %w[javascript universal],
      ".ts"    => %w[javascript universal],
      ".tsx"   => %w[javascript universal],
    }.freeze

    class << self
      def axioms_data
        @axioms_data ||= File.exist?(AXIOMS_FILE) ? YAML.safe_load_file(AXIOMS_FILE) : {}
      end

      def all_axioms
        axioms_data.flat_map { |lang, rules| (rules || []).map { |r| r.merge("language" => lang) } }
      end

      def axioms_for(language)
        axioms_data[language.to_s] || []
      end

      def languages_for_file(filename)
        ext = File.extname(filename).downcase
        EXTENSION_MAP[ext] || %w[universal]
      end

      def check(code, filename: "code")
        violations = []
        languages = languages_for_file(filename)

        languages.each do |lang|
          axioms_for(lang).each do |axiom|
            pattern_str = axiom["detect"]
            next if pattern_str.nil? # Advisory-only axioms

            begin
              pattern = Regexp.new(pattern_str, Regexp::MULTILINE)
            rescue RegexpError
              next
            end

            next unless code.match?(pattern)

            violations << {
              layer: :language_axiom,
              language: lang,
              axiom_id: axiom["id"],
              axiom_name: axiom["name"],
              message: axiom["suggest"],
              severity: axiom["severity"]&.to_sym || :info,
              autofix: axiom["autofix"] || false,
              file: filename,
            }
          end
        end

        violations
      end

      def summary
        counts = {}
        axioms_data.each { |lang, rules| counts[lang] = (rules || []).size }
        counts["total"] = counts.values.sum
        counts
      end
    end
  end

  # AxiomStats - Provides statistics and summary views for language axioms
  module AxiomStats
    extend self

    def stats
      axioms = load_axioms
      
      return { error: "No axioms found" } if axioms.empty?

      {
        total: axioms.size,
        by_category: count_by_key(axioms, "category"),
        by_protection: count_by_key(axioms, "protection"),
        axioms: axioms
      }
    end

    def summary
      data = stats
      return data if data[:error]

      lines = []
      lines << "Language Axioms Summary"
      lines << "=" * 40
      lines << ""
      lines << "Total axioms: #{data[:total]}"
      lines << ""
      lines << "By Category:"
      data[:by_category].sort_by { |_, count| -count }.each do |category, count|
        lines << "  #{category.ljust(20)} #{count}"
      end
      lines << ""
      lines << "By Protection Level:"
      data[:by_protection].sort_by { |_, count| -count }.each do |protection, count|
        lines << "  #{protection.ljust(20)} #{count}"
      end
      lines << ""
      
      lines.join("\n")
    end

    def top_categories(limit: 5)
      data = stats
      return [] if data[:error]
      
      data[:by_category].sort_by { |_, count| -count }.first(limit)
    end

    private

    def load_axioms
      # MASTER.root points to the MASTER2 directory when running from within MASTER2
      # or to pub4 directory when running from outside
      axioms_paths = [
        File.join(MASTER.root, "data", "axioms.yml"),              # When run from MASTER2
        File.join(MASTER.root, "MASTER2", "data", "axioms.yml")   # When run from pub4
      ]
      
      axioms_file = axioms_paths.find { |path| File.exist?(path) }
      
      return [] unless axioms_file
      
      begin
        YAML.safe_load_file(axioms_file) || []
      rescue => e
        []
      end
    end

    def count_by_key(axioms, key)
      counts = Hash.new(0)
      axioms.each do |axiom|
        value = axiom[key]
        counts[value] += 1 if value
      end
      counts
    end
  end
end
