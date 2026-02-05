# frozen_string_literal: true

module MASTER
  # Dual violation detection: literal (regex/AST) + conceptual (LLM semantic)
  # Catches both syntactic violations and semantic principle violations
  module Violations
    # Literal patterns for fast detection (no LLM needed)
    LITERAL_PATTERNS = {
      # KISS violations
      deep_nesting: {
        pattern: /^(\s{8,})(if|unless|case|while|until|for|begin)/,
        principle: 'KISS',
        message: 'Deep nesting detected (4+ levels)',
        severity: :warning
      },
      long_line: {
        pattern: /^.{120,}$/,
        principle: 'KISS',
        message: 'Line exceeds 120 characters',
        severity: :info
      },
      complex_conditional: {
        pattern: /if\s+.*&&.*&&|if\s+.*\|\|.*\|\|/,
        principle: 'KISS',
        message: 'Complex conditional with multiple operators',
        severity: :warning
      },

      # DRY violations
      magic_number: {
        pattern: /[^0-9a-z_]([2-9]\d{2,}|[1-9]\d{3,})[^0-9a-z_]/i,
        principle: 'DRY',
        message: 'Magic number detected (should be named constant)',
        severity: :info
      },
      repeated_string: {
        pattern: nil, # Handled specially
        principle: 'DRY',
        message: 'Repeated string literal',
        severity: :warning
      },

      # YAGNI violations
      unused_variable: {
        pattern: /^\s*(\w+)\s*=(?!.*\1)/,
        principle: 'YAGNI',
        message: 'Potentially unused variable assignment',
        severity: :info
      },
      commented_code: {
        pattern: /^\s*#\s*(def |class |module |if |unless |case |while )/,
        principle: 'YAGNI',
        message: 'Commented out code detected',
        severity: :warning
      },

      # Single Responsibility violations
      many_requires: {
        pattern: nil, # Count-based
        principle: 'Single Responsibility',
        message: 'Too many requires (high coupling)',
        severity: :warning
      },

      # Law of Demeter violations
      method_chain: {
        pattern: /\w+\.\w+\.\w+\.\w+/,
        principle: 'Law of Demeter',
        message: 'Long method chain (train wreck)',
        severity: :warning
      },

      # Command Query Separation
      query_with_side_effect: {
        pattern: /def\s+(get_|find_|is_|has_|can_)\w+.*\n(?:.*\n)*?.*(?:save|update|delete|destroy|write|remove)/m,
        principle: 'Command Query Separation',
        message: 'Query method appears to have side effects',
        severity: :error
      },

      # Fail Fast violations
      late_nil_check: {
        pattern: /(\w+)\.[^.]+\n(?:.*\n)*?.*\1\.nil\?/m,
        principle: 'Fail Fast',
        message: 'Nil check after object use',
        severity: :warning
      },

      # Meaningful names
      short_variable: {
        pattern: /\b([a-z])\s*=/,
        principle: 'Meaningful Names',
        message: 'Single letter variable name',
        severity: :info
      },
      abbreviated_name: {
        pattern: /\b(str|arr|obj|tmp|val|num|cnt|idx|ptr|buf|msg|err|usr|pwd|cfg|env)\b/,
        principle: 'Meaningful Names',
        message: 'Abbreviated variable name',
        severity: :info
      },

      # No Side Effects
      global_mutation: {
        pattern: /\$\w+\s*[+\-*\/]?=/,
        principle: 'No Side Effects',
        message: 'Global variable mutation',
        severity: :error
      },
      class_variable_mutation: {
        pattern: /@@\w+\s*[+\-*\/]?=/,
        principle: 'No Side Effects',
        message: 'Class variable mutation',
        severity: :warning
      },

      # Bare rescue (swallows errors silently)
      bare_rescue: {
        pattern: /rescue\s*$/,
        principle: 'Fail Fast',
        message: 'Bare rescue swallows errors silently',
        severity: :warning
      },

      # String slice magic numbers
      string_slice_magic: {
        pattern: /\[0\.\.\d{3,}\]/,
        principle: 'DRY',
        message: 'Magic number in string slice (use constant)',
        severity: :info
      },

      # Sleep magic numbers
      sleep_magic: {
        pattern: /sleep\s+\d+(\.\d+)?(?!\s*#)/,
        principle: 'DRY',
        message: 'Magic number in sleep (use constant)',
        severity: :info
      },

      # Limit magic numbers (.first/.last)
      limit_magic: {
        pattern: /\.(first|last)\(\d{2,}\)/,
        principle: 'DRY',
        message: 'Magic number in limit (use constant)',
        severity: :info
      },

      # Few Arguments
      many_parameters: {
        pattern: /def\s+\w+\s*\(([^)]*,){4,}[^)]*\)/,
        principle: 'Few Arguments',
        message: 'Method has too many parameters (>4)',
        severity: :warning
      },

      # Small Functions
      long_method: {
        pattern: nil, # Count-based
        principle: 'Small Functions',
        message: 'Method exceeds 20 lines',
        severity: :warning
      }
    }.freeze

    # Conceptual patterns for LLM semantic analysis
    CONCEPTUAL_CHECKS = {
      kiss: {
        prompt: 'Is this code unnecessarily complex? Could it be simpler while maintaining functionality?',
        examples: [
          'Using metaprogramming when a simple method would work',
          'Over-abstracted class hierarchies for simple problems',
          'Callback chains that obscure control flow'
        ]
      },
      dry: {
        prompt: 'Is there duplicated logic or repeated patterns that should be extracted?',
        examples: [
          'Similar error handling repeated across methods',
          'Same validation logic in multiple places',
          'Repeated data transformations'
        ]
      },
      yagni: {
        prompt: 'Is there code built for hypothetical future requirements that are not needed now?',
        examples: [
          'Unused method parameters "for future use"',
          'Abstract factories with single implementation',
          'Configuration options nobody uses'
        ]
      },
      single_responsibility: {
        prompt: 'Does this class/module have more than one reason to change?',
        examples: [
          'Class handling both business logic and persistence',
          'Method doing calculation and formatting and logging',
          'Module mixing UI concerns with data processing'
        ]
      },
      separation_of_concerns: {
        prompt: 'Are different concerns properly isolated or are they tangled together?',
        examples: [
          'SQL queries embedded in view templates',
          'Business rules in controllers',
          'Logging mixed with core logic'
        ]
      },
      open_closed: {
        prompt: 'Would adding new behavior require modifying existing code instead of extending it?',
        examples: [
          'Case statements that need modification for each new type',
          'If-else chains checking object types',
          'Hard-coded behavior that should be pluggable'
        ]
      },
      dependency_inversion: {
        prompt: 'Does high-level code depend on low-level details instead of abstractions?',
        examples: [
          'Business logic directly calling database methods',
          'Hard-coded API clients without interfaces',
          'Direct file system access in core modules'
        ]
      },
      law_of_demeter: {
        prompt: 'Does the code reach through objects to access their internals?',
        examples: [
          'user.account.subscription.plan.price',
          'Accessing nested hash keys deeply',
          'Calling methods on objects returned by other methods'
        ]
      },
      fail_fast: {
        prompt: 'Does the code validate inputs early or wait until problems propagate?',
        examples: [
          'Processing continues after detecting invalid state',
          'Errors are caught and silently ignored',
          'Nil checks at the end instead of the beginning'
        ]
      },
      immutability: {
        prompt: 'Is mutable state being modified when immutable approaches would work?',
        examples: [
          'Arrays modified in place instead of mapped',
          'Instance variables changed after initialization',
          'Shared state modified by multiple methods'
        ]
      }
      }.freeze
    VAR_USAGE_PATTERN = /(\w+)\./.freeze

    class << self
      # Run both literal and conceptual detection
      def analyze(code, path: nil, llm: nil, conceptual: true)
        results = {
          literal: [],
          conceptual: [],
          summary: { errors: 0, warnings: 0, info: 0 }
        }

        # Phase 1: Literal detection (fast, no LLM)
        results[:literal] = detect_literal(code, path)
        results[:literal].each do |v|
          results[:summary][v[:severity]] += 1
        end

        # Phase 2: Conceptual detection (requires LLM)
        if conceptual && llm
          results[:conceptual] = detect_conceptual(code, path, llm)
          results[:conceptual].each do |v|
            results[:summary][:warnings] += 1
          end
        end

        results
      end

      # Literal pattern matching only
      def detect_literal(code, path = nil)
        violations = []
        lines = code.lines

        LITERAL_PATTERNS.each do |name, config|
          next unless config[:pattern]
          next if name == :late_nil_check

          pattern = config[:pattern]
          multiline = (pattern.options & Regexp::MULTILINE) != 0

          if multiline
            matches = code.scan(pattern)
            matches.each do |match|
              match_value = match.is_a?(Array) ? match.first : match
              line_num = find_line_number(code, match_value)
              violations << {
                type: :literal,
                name: name,
                principle: config[:principle],
                message: config[:message],
                severity: config[:severity],
                line: line_num,
                match: match_value.to_s[0..50]
              }
            end
          else
            lines.each_with_index do |line, idx|
              line.scan(pattern).each do |match|
                match_value = match.is_a?(Array) ? match.first : match
                violations << {
                  type: :literal,
                  name: name,
                  principle: config[:principle],
                  message: config[:message],
                  severity: config[:severity],
                  line: idx + 1,
                  match: match_value.to_s[0..50]
                }
              end
            end
          end
        end

        # Count-based checks
        violations += check_method_lengths(code, lines)
        violations += check_require_count(code)
        violations += check_repeated_strings(code)
        violations += check_late_nil_check(lines)

        violations
      end

      # Conceptual LLM-based detection
      def detect_conceptual(code, path, llm)
        violations = []

        # Sample checks to avoid excessive LLM calls
        checks_to_run = CONCEPTUAL_CHECKS.keys.sample(3)

        checks_to_run.each do |principle|
          config = CONCEPTUAL_CHECKS[principle]

          prompt = <<~PROMPT
            Analyze this Ruby code for #{principle.to_s.upcase.tr('_', ' ')} violations.

            #{config[:prompt]}

            Examples of violations:
            #{config[:examples].map { |e| "- #{e}" }.join("\n")}

            CODE:
            ```ruby
            #{code[0..3000]}
            ```

            If there are violations, list them with line numbers.
            If the code is clean for this principle, say "No violations found."
            Be specific and cite actual code, not hypotheticals.
          PROMPT

          result = llm.chat(prompt, tier: :cheap)
          next unless result.ok?

          response = result.value.to_s.downcase
          next if response.include?('no violations') || response.include?('code is clean')

          violations << {
            type: :conceptual,
            principle: principle.to_s.tr('_', ' ').upcase,
            analysis: result.value,
            severity: :warning
          }
        end

        violations
      end

      # Quick scan for a single file
      def quick_scan(path, llm: nil)
        return { error: 'File not found' } unless File.exist?(path)

        code = File.read(path)
        analyze(code, path: path, llm: llm, conceptual: llm.nil? ? false : true)
      end

      # Full scan of a directory
      def scan_directory(dir, llm: nil, extensions: %w[.rb])
        results = {}

        Dir.glob(File.join(dir, '**', '*')).each do |path|
          next unless extensions.any? { |ext| path.end_with?(ext) }
          next if path.include?('/test/') || path.include?('/spec/')

          results[path] = quick_scan(path, llm: llm)
        end

        results
      end

      def report(results)
        output = []
        output << "Violations Report"
        output << "=" * 60

        if results[:literal].any?
          output << "\nLiteral Violations (#{results[:literal].size}):"
          results[:literal].each do |v|
            icon = case v[:severity]
                   when :error then '❌'
                   when :warning then '⚠️'
                   else 'ℹ️'
                   end
            output << "  #{icon} [#{v[:principle]}] #{v[:message]}"
            output << "     Line #{v[:line]}: #{v[:match]}" if v[:line]
          end
        end

        if results[:conceptual].any?
          output << "\nConceptual Violations (#{results[:conceptual].size}):"
          results[:conceptual].each do |v|
            output << "  🧠 [#{v[:principle]}]"
            output << "     #{v[:analysis][0..200]}..."
          end
        end

        output << "\nSummary: #{results[:summary][:errors]} errors, #{results[:summary][:warnings]} warnings, #{results[:summary][:info]} info"
        output.join("\n")
      end

      private

      def find_line_number(code, match)
        return nil unless match
        index = code.index(match.to_s)
        return nil unless index
        code[0..index].count("\n") + 1
      end

      def check_method_lengths(code, lines)
        violations = []
        method_start = nil
        method_name = nil
        depth = 0

        lines.each_with_index do |line, idx|
          if line =~ /^\s*def\s+(\w+)/
            method_start = idx
            method_name = $1
            depth = 1
          elsif method_start && line.strip == 'end'
            depth -= 1
            if depth == 0
              length = idx - method_start
              if length > 20
                violations << {
                  type: :literal,
                  name: :long_method,
                  principle: 'Small Functions',
                  message: "Method '#{method_name}' is #{length} lines (>20)",
                  severity: :warning,
                  line: method_start + 1
                }
              end
              method_start = nil
            end
          elsif method_start && line =~ /^\s*(class|module|def|if|unless|case|while|until|for|begin|do)\b/
            depth += 1
          end
        end

        violations
      end

      def check_require_count(code)
        requires = code.scan(/^require/).size + code.scan(/^require_relative/).size
        return [] if requires <= 10

        [{
          type: :literal,
          name: :many_requires,
          principle: 'Single Responsibility',
          message: "File has #{requires} requires (high coupling)",
          severity: :warning,
          line: 1
        }]
      end

      def check_repeated_strings(code)
        violations = []
        strings = code.scan(/"[^"]{8,}"|'[^']{8,}'/).flatten
        counts = strings.tally

        counts.each do |str, count|
          next if count < 3

          violations << {
            type: :literal,
            name: :repeated_string,
            principle: 'DRY',
            message: "String #{str[0..30]}... repeated #{count} times",
            severity: :warning
          }
        end

        violations
      end

      def check_late_nil_check(lines)
        config = LITERAL_PATTERNS[:late_nil_check]
        return [] unless config

        violations = []
        used_vars = {}
        lines.each_with_index do |line, idx|
          match = line.match(/(\w+)\.nil\?/)
          if match
            var = match[1]
            if used_vars[var]
              violations << {
                type: :literal,
                name: :late_nil_check,
                principle: config[:principle],
                message: config[:message],
                severity: config[:severity],
                line: idx + 1,
                match: line.strip[0..50]
              }
            end
          end

          line.scan(VAR_USAGE_PATTERN).each { |found| used_vars[found[0]] = true }
        end
        violations
      end
    end
  end
end
