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
        axioms ||= defined?(Constitution) ? Constitution.axioms : DB.axioms
        {
          filename: filename,
          line: check_lines(code, filename),
          unit: check_units(code, filename),
          file: check(code, axioms: axioms, filename: filename),
        }
      end

      # Analyze entire framework (multiple files)
      def analyze_framework(files, axioms: nil)
        axioms ||= defined?(Constitution) ? Constitution.axioms : DB.axioms
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
        # Load axioms from Constitution.axioms if not provided (includes YAML with detect patterns)
        axioms ||= defined?(Constitution) ? Constitution.axioms : DB.axioms
        violations = []

        LAYERS.each do |layer|
          layer_violations = send(:"check_#{layer}", code, axioms, filename)
          violations.concat(layer_violations)
        end

        # Add additional checks from merged Validator
        violations.concat(check_srp(code, filename: filename))
        violations.concat(check_kiss_complexity(code, filename: filename))
        violations.concat(check_dry_violations(code, filename: filename))
        violations.concat(check_file_size_violation(code, filename: filename))

        { filename: filename, violations: violations, layers_checked: LAYERS }
      end

      # Validate LLM response text by extracting and checking code blocks
      # Merged from Validator for ONE_SOURCE compliance
      def validate_llm_response(text)
        issues = []

        # Check for code blocks
        if text.include?('```')
          code_blocks = text.scan(/```\w*\n(.*?)```/m).flatten
          code_blocks.each do |code|
            result = check(code, filename: "llm_response")
            issues.concat(result[:violations])
          end
        end

        issues
      end

      # Boot-time self-check: Enforce SELF_APPLY axiom on own source
      # Checks key source files for ABSOLUTE protection violations only
      # Does NOT halt boot - warns only via Dmesg if violations found
      def self_check!
        # Skip if already ran
        return @last_self_check if @last_self_check

        # Check only result.rb to keep boot fast and avoid recursion
        # result.rb is the core monad/result type used throughout - critical to validate
        # Checking enforcement.rb itself would create recursion risk
        key_files = %w[result.rb]
        violations = []

        begin
          key_files.each do |f|
            path = File.join(MASTER.root, "lib", f)
            next unless File.exist?(path)

            code = File.read(path)

            result = check(code, filename: f)

            # Filter for ABSOLUTE protection violations only
            absolute_violations = result[:violations].select do |v|
              v[:protection] == "ABSOLUTE"
            end

            violations.concat(absolute_violations)
          end
        rescue StandardError => e
          # Gracefully handle any errors during self-check
          @last_self_check = {
            timestamp: Time.now,
            files_checked: 0,
            absolute_violations: [],
            passed: false,
            error: e.message
          }
          return @last_self_check
        end

        @last_self_check = {
          timestamp: Time.now,
          files_checked: key_files.size,
          absolute_violations: violations,
          passed: violations.empty?
        }

        # Warn if violations found (don't halt boot)
        unless violations.empty?
          if defined?(Dmesg)
            Dmesg.warn("SELF_APPLY: #{violations.size} ABSOLUTE violations in own source")
          end
        end

        @last_self_check
      end

      # Get last self-check result
      def last_self_check
        @last_self_check || { timestamp: nil, files_checked: 0, absolute_violations: [], passed: true }
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

  # Constitution - Enforcement of governance policies for safe autonomous operation
  module Constitution
    extend self

    @rules_cache = nil
    @axioms_cache = nil
    @council_cache = nil
    @principles_cache = nil
    @workflows_cache = nil

    # Load and cache constitution rules, with sensible defaults if file is missing
    def rules
      return @rules_cache if @rules_cache

      constitution_path = File.join(MASTER.root, "data", "constitution.yml")
      
      @rules_cache = if File.exist?(constitution_path)
        YAML.safe_load_file(constitution_path)
      else
        # Sensible defaults when constitution.yml is missing
        {
          "safety_policies" => {
            "self_modification" => { "require_staging" => true },
            "environment_control" => { "direct_control" => false }
          },
          "tool_permissions" => {
            "granted" => ["shell_command", "code_execution", "file_write"]
          },
          "shell_patterns" => {
            "allowed" => ["^(ls|pwd|echo|git|cat|head|tail|wc|find|grep)", "^ruby", "^bundle"],
            "blocked" => ["rm -rf /", "DROP TABLE", "mkfs", "dd if=", ":(){ :|:& };:"]
          },
          "protected_paths" => ["data/constitution.yml", "/etc/", "/usr/", "/sys/"],
          "resource_limits" => {
            "max_file_size" => 1048576,
            "max_concurrent_tools" => 5,
            "max_staging_files" => 10,
            "max_shell_output" => 10000
          },
          "staging" => {
            "validation" => {
              "default_command" => "ruby -c",
              "require_tests" => true
            }
          }
        }
      end
      
      @rules_cache
    end

    # Load axioms from constitution or fallback to axioms.yml
    def axioms
      return @axioms_cache if @axioms_cache
      
      # Try loading from constitution first
      if rules["axioms"]
        @axioms_cache = rules["axioms"]
      else
        # Fallback to separate axioms.yml file
        axioms_path = File.join(MASTER.root, "data", "axioms.yml")
        @axioms_cache = File.exist?(axioms_path) ? YAML.safe_load_file(axioms_path) : []
      end
      
      @axioms_cache
    end

    # Load council from constitution or fallback to council.yml
    def council
      return @council_cache if @council_cache
      
      # Try loading from constitution first
      if rules["council"]
        @council_cache = rules["council"]
      else
        # Fallback to separate council.yml file
        council_path = File.join(MASTER.root, "data", "council.yml")
        @council_cache = File.exist?(council_path) ? YAML.safe_load_file(council_path) : []
      end
      
      @council_cache
    end

    # Load principles from constitution (SOLID, Clean Code, etc.)
    def principles
      return @principles_cache if @principles_cache
      
      @principles_cache = rules["principles"] || {}
      @principles_cache
    end

    # Load workflows from constitution (8-phase workflow)
    def workflows
      return @workflows_cache if @workflows_cache
      
      @workflows_cache = rules["workflows"] || {}
      @workflows_cache
    end

    # Reload all cached data
    def reload!
      @rules_cache = nil
      @axioms_cache = nil
      @council_cache = nil
      @principles_cache = nil
      @workflows_cache = nil
      rules
    end

    # Validate operation against constitution rules
    def check_operation(op, context = {})
      case op
      when :self_modification
        if rules.dig("safety_policies", "self_modification", "require_staging")
          unless context[:staged]
            return Result.err("Self-modification requires staging")
          end
        end
        Result.ok
      
      when :environment_control
        if rules.dig("safety_policies", "environment_control", "direct_control") == false
          return Result.err("Direct environment control not permitted")
        end
        Result.ok
      
      when :shell_command
        cmd = context[:command] || ""
        check_shell_command(cmd)
      
      when :file_write
        path = context[:path] || ""
        check_file_write(path)
      
      else
        Result.ok
      end
    end

    # Check if a tool is permitted
    def permission?(tool)
      granted = rules.dig("tool_permissions", "granted") || []
      granted.include?(tool.to_s)
    end

    # Check if a path is protected
    def protected_file?(path)
      protected = rules["protected_paths"] || []
      expanded = File.expand_path(path)
      
      protected.any? do |protected_path|
        # For absolute paths, compare directly; for relative, expand from root
        expanded_protected = if protected_path.start_with?("/")
          protected_path
        else
          File.expand_path(protected_path, MASTER.root)
        end
        
        expanded.start_with?(expanded_protected) || expanded == expanded_protected
      end
    end

    # Get a resource limit value
    def limit(key)
      rules.dig("resource_limits", key.to_s)
    end

    private

    def check_shell_command(cmd)
      blocked = rules.dig("shell_patterns", "blocked") || []
      allowed = rules.dig("shell_patterns", "allowed") || []
      
      # Check blocked patterns first
      blocked.each do |pattern|
        if cmd.include?(pattern) || cmd.match?(Regexp.new(pattern))
          return Result.err("Shell command blocked by constitution: #{pattern}")
        end
      end
      
      # Check allowed patterns
      if allowed.any?
        unless allowed.any? { |pattern| cmd.match?(Regexp.new(pattern)) }
          return Result.err("Shell command not in allowed list")
        end
      end
      
      Result.ok
    end

    def check_file_write(path)
      if protected_file?(path)
        Result.err("File write to protected path: #{path}")
      else
        Result.ok
      end
    end
  end
end
