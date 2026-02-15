# frozen_string_literal: true

require "yaml"

# Load all code review sub-modules
require_relative "code_review/violations"
require_relative "code_review/smells"
require_relative "code_review/bug_hunting"
require_relative "code_review/engine"
require_relative "code_review/llm_friendly"
require_relative "code_review/audit"
require_relative "code_review/cross_ref"

# Load enforcement modules
require_relative "enforcement/layers"
require_relative "enforcement/scopes"

module MASTER
  module Review
    # Scanner - Automated checks learned from deep analysis sessions
    # These patterns were discovered through cross-referencing and execution tracing
    module Scanner
      extend self

      # The analysis prompt template - generates categorized opportunities
      OPPORTUNITY_PROMPT = <<~PROMPT
        Analyze this codebase and identify concrete improvement opportunities.

        For each category, list 5-15 specific, actionable items.
        Be precise - reference specific files, line numbers, patterns.
        Prioritize by impact and effort.

        ## Categories:

        ### MAJOR ARCHITECTURAL OPPORTUNITIES
        Large-scale structural improvements: consolidation, patterns, abstractions,
        module boundaries, data flow, concurrency, APIs.

        ### MICRO-REFINEMENT OPPORTUNITIES  
        Small code-level improvements: idioms, naming, constants, memoization,
        type safety, error handling, Ruby style guide adherence.

        ### CLI UI/UX OPPORTUNITIES
        User experience improvements: feedback, discoverability, shortcuts,
        progress indication, error messages, help system, accessibility.

        ### TYPOGRAPHICAL OPPORTUNITIES
        Text presentation: smart quotes, dashes, symbols, Unicode,
        formatting, box drawing, bullets, spacing.

        ## Format each item as:
        - **ID**: short_snake_case_id
        - **Description**: One clear sentence
        - **Location**: File/line or "throughout"
        - **Effort**: small/medium/large
        - **Impact**: low/medium/high

        ## Codebase to analyze:
        %{code}
      PROMPT

      # Issues found in this codebase that should be auto-detected
      CHECKS = {
        namespace_prefix: {
          pattern: /^(?!.*MASTER::)(DB|LLM|Session|Pipeline)\./,
          message: "Use MASTER:: prefix for module references in bin/ scripts",
          severity: :critical,
        },
        symbol_string_fallback: {
          pattern: /\[["'][a-z_]+["']\]\s*\|\|\s*\[:[a-z_]+\]/,
          message: "Mixed string/symbol access - use symbolize_names: true in JSON.parse",
          severity: :major,
        },
        dirty_flag_missing: {
          pattern: /\.pop\(|\.shift\(|\.delete|\.clear(?!\s*#.*dirty)/,
          message: "Mutation without @dirty = true - changes won't persist",
          severity: :major,
        },
        rescue_without_type: {
          pattern: /rescue\s*$/,
          message: "Bare rescue catches all exceptions - use StandardError",
          severity: :minor,
        },
      }.freeze

      # Patterns that indicate good code
      GOOD_PATTERNS = {
        frozen_string: /^# frozen_string_literal: true/,
        module_docstring: /module \w+\n\s+# [A-Z]/,
        guard_clause: /return .* (if|unless) /,
        explicit_error: /rescue StandardError/,
        symbolize_names: /symbolize_names:\s*true/,
        language_axioms_clean: /\A(?!.*(?:inject\(\{\})|(?:update_attribute)|(?:for\s+\w+\s+in\s+))/m,
      }.freeze

      class << self
        # Generate categorized opportunities using LLM
        def opportunities(code_or_path, llm: LLM)
          code = File.exist?(code_or_path.to_s) ? aggregate_code(code_or_path) : code_or_path

          prompt = format(OPPORTUNITY_PROMPT, code: truncate_code(code))

          result = llm.ask(prompt, tier: :fast)
          return Result.err("No model available") unless result.ok?

          parse_opportunities(result.value[:content])
        rescue StandardError => e
          Result.err("Analysis failed: #{e.message}")
        end

        # Quick static analysis (no LLM)
        def analyze(code, filename: nil)
          issues = []

          CHECKS.each do |name, check|
            if code.match?(check[:pattern])
              issues << {
                check: name,
                message: check[:message],
                severity: check[:severity],
                file: filename,
              }
            end
          end

          score = GOOD_PATTERNS.count { |_, pattern| code.match?(pattern) }

          {
            issues: issues,
            score: score,
            max_score: GOOD_PATTERNS.size,
            grade: grade_for(score),
          }
        end

        def analyze_file(path)
          analyze(File.read(path), filename: File.basename(path))
        end

        def analyze_directory(dir)
          results = {}
          Dir.glob(File.join(dir, "**", "*.rb")).each do |file|
            results[file] = analyze_file(file)
          end

          {
            files: results,
            total_issues: results.values.sum { |r| r[:issues].size },
            critical: results.values.flat_map { |r| r[:issues] }.count { |i| i[:severity] == :critical },
            major: results.values.flat_map { |r| r[:issues] }.count { |i| i[:severity] == :major },
            average_score: results.values.sum { |r| r[:score] }.to_f / results.size,
          }
        end

        private

        def aggregate_code(path)
          if File.directory?(path)
            Dir.glob(File.join(path, "**", "*.rb")).map do |f|
              "# FILE: #{f}\n#{File.read(f)}"
            end.join("\n\n")
          else
            "# FILE: #{path}\n#{File.read(path)}"
          end
        end

        def truncate_code(code, max_chars: 50_000)
          return code if code.length <= max_chars

          code[0, max_chars] + "\n\n# ... truncated (#{code.length - max_chars} more chars)"
        end

        def parse_opportunities(response)
          categories = {
            architectural: [],
            micro: [],
            ui_ux: [],
            typography: [],
          }

          current_category = nil

          response.each_line do |line|
            case line
            when /ARCHITECTURAL/i
              current_category = :architectural
            when /MICRO/i
              current_category = :micro
            when /UI.?UX/i
              current_category = :ui_ux
            when /TYPO/i
              current_category = :typography
            when /^\s*-\s*\*\*(.+?)\*\*:\s*(.+)/
              next unless current_category

              categories[current_category] << {
                id: Regexp.last_match(1).strip.downcase.gsub(/\s+/, "_"),
                description: Regexp.last_match(2).strip,
              }
            when /^\d+\.\s*\*\*(.+?)\*\*\s*[-–—]\s*(.+)/
              next unless current_category

              categories[current_category] << {
                id: Regexp.last_match(1).strip.downcase.gsub(/\s+/, "_"),
                description: Regexp.last_match(2).strip,
              }
            end
          end

          Result.ok(categories)
        end

        def grade_for(score)
          case score
          when 5 then "A"
          when 4 then "B"
          when 3 then "C"
          when 2 then "D"
          else "F"
          end
        end
      end

      # FileHygiene - Clean up file formatting issues
      module FileHygiene
        extend self

        def clean(content)
          content = strip_bom(content)
          content = normalize_line_endings(content)
          content = strip_trailing_whitespace(content)
          content = ensure_final_newline(content)
          content
        end

        def clean_file(path)
          original = File.read(path)
          cleaned = clean(original)

          if original != cleaned
            Undo.track_edit(path, original) if defined?(Undo)
            File.write(path, cleaned)
            true
          else
            false
          end
        end

        def analyze(content)
          issues = []

          issues << :bom if has_bom?(content)
          issues << :crlf if has_crlf?(content)
          issues << :trailing_whitespace if has_trailing_whitespace?(content)
          issues << :no_final_newline unless ends_with_newline?(content)
          issues << :tabs if has_tabs?(content)

          issues
        end

        private

        def strip_bom(content)
          content.sub(/\A\xEF\xBB\xBF/, '')
        end

        def normalize_line_endings(content)
          content.gsub(/\r\n?/, "\n")
        end

        def strip_trailing_whitespace(content)
          content.gsub(/[ \t]+$/, '')
        end

        def ensure_final_newline(content)
          content.end_with?("\n") ? content : "#{content}\n"
        end

        def has_bom?(content)
          content.start_with?("\xEF\xBB\xBF")
        end

        def has_crlf?(content)
          content.include?("\r\n")
        end

        def has_trailing_whitespace?(content)
          content.match?(/[ \t]+$/)
        end

        def ends_with_newline?(content)
          content.end_with?("\n")
        end

        def has_tabs?(content)
          content.include?("\t")
        end
      end
    end

    # Fixer - Automated code fixes with verification and rollback
    # Modes: conservative (whitespace only), moderate (+debug), aggressive (all)
    class Fixer
      MAX_FIXES_PER_RUN = 20
      MODES = %i[conservative moderate aggressive].freeze

      FIXERS = {
        trailing_whitespace: ->(code) { code.gsub(/[ \t]+$/, "") },
        debug_code: ->(code) { code.gsub(/^\s*(binding\.pry|debugger|byebug).*\n/, "") },
        puts_debug: ->(code) { code.gsub(/^\s*puts\s+["']debug.*["'].*\n/i, "") },
        empty_lines_excess: ->(code) { code.gsub(/\n{3,}/, "\n\n") },
        trailing_newlines: ->(code) { code.rstrip + "\n" },
        mixed_indentation: ->(code) { code.gsub(/^(\t+)/) { |m| "  " * m.length } },
        crlf_to_lf: ->(code) { code.gsub("\r\n", "\n") },
        bom_strip: ->(code) { code.sub(/\A\xEF\xBB\xBF/, "") },
        # Language axiom auto-fixes
        freeze_constants: ->(code) { code.gsub(/^(\s*[A-Z][A-Z_]*\s*=\s*[\[{].*)$/m) { |m| m.include?(".freeze") ? m : m.rstrip + ".freeze" } },
        safe_navigation: ->(code) { code.gsub(/(\w+)\s*&&\s*\1\.(\w+)/) { "#{Regexp.last_match(1)}&.#{Regexp.last_match(2)}" } },
      }.freeze

      MODE_FIXES = {
        conservative: %i[trailing_whitespace empty_lines_excess trailing_newlines crlf_to_lf bom_strip],
        moderate: %i[trailing_whitespace empty_lines_excess trailing_newlines puts_debug crlf_to_lf bom_strip mixed_indentation],
        aggressive: FIXERS.keys,
      }.freeze

      def initialize(mode: :conservative)
        @mode = MODES.include?(mode) ? mode : :conservative
        @fixes_applied = []
        @backups = {}
      end

      attr_reader :fixes_applied, :mode

      def fix(file, violations = nil)
        return Result.err("File not found: #{file}") unless File.exist?(file)

        code = File.read(file)
        original = code.dup
        @backups[file] = original

        fixable = violations&.select { |v| can_fix?(v[:type]) } || auto_detect(code)
        fixable = fixable.take(MAX_FIXES_PER_RUN)

        return Result.ok(file: file, fixed: 0, message: "No fixable violations") if fixable.empty?

        fixed_count = 0
        fixable.each do |violation|
          type = violation[:type]&.to_sym
          next unless can_fix?(type)

          fixer = FIXERS[type]
          next unless fixer

          new_code = fixer.call(code)
          if new_code != code
            code = new_code
            fixed_count += 1
            @fixes_applied << { file: file, type: type }
          end
        end

        return Result.ok(file: file, fixed: 0, message: "No changes needed") if code == original

        unless valid_syntax?(code, file)
          return Result.err("Fix produced invalid syntax - not writing")
        end

        File.write(file, code)

        Result.ok(
          file: file,
          fixed: fixed_count,
          types: @fixes_applied.select { |f| f[:file] == file }.map { |f| f[:type] }
        )
      end

      def fix_all(files, violations_by_file = {})
        results = []

        files.each do |file|
          violations = violations_by_file[file] || []
          result = fix(file, violations)
          results << result
        end

        successful = results.count(&:ok?)
        total_fixed = results.select(&:ok?).sum { |r| r.value[:fixed] }

        Result.ok(
          files_processed: files.size,
          files_fixed: successful,
          total_fixes: total_fixed,
          details: results.map { |r| r.ok? ? r.value : { error: r.error } }
        )
      end

      def fix_directory(dir, pattern: "**/*.rb")
        files = Dir.glob(File.join(dir, pattern))
        fix_all(files)
      end

      def rollback(file)
        return Result.err("No backup for #{file}") unless @backups[file]

        File.write(file, @backups[file])
        @backups.delete(file)

        Result.ok("Rolled back #{file}")
      end

      def rollback_all
        @backups.each do |file, content|
          File.write(file, content)
        end

        count = @backups.size
        @backups.clear
        @fixes_applied.clear

        Result.ok("Rolled back #{count} files")
      end

      private

      def can_fix?(type)
        type = type.to_sym
        allowed = MODE_FIXES[@mode] || []
        allowed.include?(type)
      end

      def auto_detect(code)
        violations = []

        violations << { type: :trailing_whitespace } if code =~ /[ \t]+$/
        violations << { type: :empty_lines_excess } if code =~ /\n{3,}/
        violations << { type: :trailing_newlines } if code =~ /\n\n+\z/
        violations << { type: :debug_code } if code =~ /\b(binding\.pry|debugger|byebug)\b/
        violations << { type: :puts_debug } if code =~ /^\s*puts\s+["']debug/i
        violations << { type: :mixed_indentation } if code =~ /^\t/
        violations << { type: :crlf_to_lf } if code.include?("\r\n")
        violations << { type: :bom_strip } if code.start_with?("\xEF\xBB\xBF")

        violations
      end

      def valid_syntax?(code, file)
        ext = File.extname(file).downcase
        case ext
        when ".rb"
          valid_ruby?(code)
        when ".yml", ".yaml"
          valid_yaml?(code)
        when ".json"
          valid_json?(code)
        else
          true
        end
      end

      def valid_ruby?(code)
        RubyVM::InstructionSequence.compile(code)
        true
      rescue SyntaxError
        false
      end

      def valid_yaml?(code)
        require "yaml"
        YAML.safe_load(code)
        true
      rescue StandardError
        false
      end

      def valid_json?(code)
        require "json"
        JSON.parse(code)
        true
      rescue StandardError
        false
      end
    end

    # Enforcer - 6-layer axiom enforcement at 4 scopes
    # Layers: Literal → Lexical → Conceptual → Semantic → Cognitive → Language Axiom
    # Scopes: Line → Unit → File → Framework
    module Enforcer
      extend self
      extend Enforcement::Layers
      extend Enforcement::Scopes

      LAYERS = %i[literal lexical conceptual semantic cognitive language_axiom].freeze
      SCOPES = %i[line unit file framework].freeze
      SMELLS_FILE = File.join(__dir__, "..", "data", "smells.yml")

      # MASTER2 contribution rules and architecture
      ARCHITECTURE = {
        rules: {
          new_files: {
            mandate: "No new files without justification",
            guidelines: [
              "Check if concept fits inside existing module first",
              "New file only justified if would exceed 200 lines when added to existing code",
              "Prefer adding methods to existing modules over creating new modules"
            ]
          },
          file_size: {
            guidelines: [
              "Files under 30 lines should be merged into parent module",
              "Target: 15-25 files in lib/, not 60+"
            ]
          },
          pr_rules: {
            guidelines: [
              "Never create a PR that overlaps with an existing open PR",
              "Every PR must list which existing files it modifies (not just new files)",
              "Bug fixes and new features must be in separate PRs"
            ]
          }
        },
        canonical_map: {
          "result.rb" => "Result monad (do not duplicate)",
          "llm.rb" => "All LLM/OpenRouter logic including context window management",
          "executor.rb" => "Tool dispatch, permission gates, safety guards",
          "pipeline.rb" => "Pipeline processing (with stages.rb)",
          "stages.rb" => "Pipeline stages",
          "code_review.rb" => "All static analysis (smells, violations, bug hunting)",
          "introspection.rb" => "All self-analysis (critique, reflection)",
          "self_test.rb" => "All testing and self-repair",
          "enforcement.rb" => "Axiom enforcement (single entry point)"
        }
      }.freeze

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

        # Get canonical file→responsibility mapping
        def architecture_map
          ARCHITECTURE[:canonical_map]
        end

        # Get contribution rules as structured data
        def contribution_rules
          ARCHITECTURE[:rules]
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
end

# Backward-compatible aliases
CodeReview = MASTER::Review::Scanner
AutoFixer = MASTER::Review::Fixer
Enforcement = MASTER::Review::Enforcer
QualityStandards = MASTER::Review::Enforcer
FileHygiene = MASTER::Review::Scanner::FileHygiene
