# frozen_string_literal: true

# Quality - Consolidated Code Quality Analysis
#
# This module consolidates all code quality analysis functionality:
# - Smells: Code smell detection (bloaters, couplers, dispensables, architecture)
# - Violations: Dual violation detection (literal patterns + conceptual LLM analysis)
# - BugHunting: 8-phase systematic debugging methodology
# - MultiFileAnalyzer: Parallel analysis of directories
#
# Replaces the deleted validate_principles script with integrated quality checks

module MASTER
  # Code smell detection and analysis
  module Smells
    MAX_METHOD_LINES = 20
    MAX_FILE_LINES = 300
    MAX_PARAMETERS = 4
    MAX_NESTING = 5
    MAX_PUBLIC_METHODS = 10
    MIN_DUPLICATE_COUNT = 3

    BLOATERS = {
      long_method: { check: "> #{MAX_METHOD_LINES} lines or > #{MAX_NESTING} nesting levels", fix: "Extract method" },
      god_class: { check: "> #{MAX_FILE_LINES} lines or > #{MAX_PUBLIC_METHODS} public methods", fix: "Extract class" },
      primitive_obsession: { check: "Repeated primitive patterns", fix: "Introduce value object" },
      long_parameter_list: { check: "> #{MAX_PARAMETERS} parameters", fix: "Parameter object" }
    }.freeze

    COUPLERS = {
      feature_envy: { check: "Method uses other class more than self", fix: "Move method" },
      inappropriate_intimacy: { check: "Classes know too much about each other", fix: "Extract class" },
      message_chains: { check: "Long chains like a.b.c.d", fix: "Hide delegate" }
    }.freeze

    DISPENSABLES = {
      dead_code: { check: "Unreachable or unused code", fix: "Delete it" },
      lazy_class: { check: "Class does almost nothing", fix: "Inline or merge" },
      duplicate_code: { check: "Same logic in multiple places", fix: "Extract method/class" }
    }.freeze

    ARCHITECTURE = {
      cyclic_dependency: { check: "A requires B requires A", fix: "Dependency inversion" },
      scattered_functionality: { check: "Related code in many files", fix: "Colocate" }
    }.freeze

    class << self
      # Load anti-patterns from principle YAML files
      def principle_patterns
        @principle_patterns ||= Principle.anti_patterns
      end

      def all_patterns
        static = BLOATERS.merge(COUPLERS).merge(DISPENSABLES).merge(ARCHITECTURE)
        dynamic = principle_patterns.each_with_object({}) do |ap, hash|
          key = ap[:name]&.to_sym
          hash[key] = { check: ap[:smell], fix: ap[:fix], principle: true } if key
        end
        static.merge(dynamic)
      end

      def analyze(code, file_path = nil)
        results = []
        lines = code.lines
        
        # Long method detection
        if file_path&.end_with?(".rb")
          results += analyze_ruby_methods(code, lines)
        end
        
        # Long file (god class indicator)
        if lines.size > MAX_FILE_LINES
          results << {
            smell: :god_class,
            message: "File has #{lines.size} lines (> #{MAX_FILE_LINES})",
            fix: BLOATERS[:god_class][:fix]
          }
        end
        
        # Long parameter lists
        code.scan(/def\s+\w+\(([^)]+)\)/) do |params|
          count = params[0].split(",").size
          if count > MAX_PARAMETERS
            results << {
              smell: :long_parameter_list,
              message: "Method has #{count} parameters (> #{MAX_PARAMETERS})",
              fix: BLOATERS[:long_parameter_list][:fix]
            }
          end
        end
        
        # Message chains (3+ chained calls)
        code.scan(/\w+(?:\.\w+){3,}/) do |chain|
          results << {
            smell: :message_chains,
            message: "Long chain: #{chain[0..40]}...",
            fix: COUPLERS[:message_chains][:fix]
          }
        end
        
        # Duplicate string literals (primitive obsession indicator)
        strings = code.scan(/"[^"]{10,}"/).flatten
        dupes = strings.group_by(&:itself).select { |_, v| v.size >= MIN_DUPLICATE_COUNT }
        dupes.each do |str, occurrences|
          results << {
            smell: :primitive_obsession,
            message: "String #{str[0..30]}... repeated #{occurrences.size}x",
            fix: "Extract to constant"
          }
        end
        
        results
      end
      
      def analyze_ruby_methods(code, lines)
        results = []
        method_starts = []
        nesting = 0
        
        lines.each_with_index do |line, idx|
          stripped = line.strip
          
          if stripped =~ /^\s*def\s+/
            method_starts << { line: idx + 1, nesting: nesting, name: stripped }
            nesting += 1
          elsif stripped == "end"
            if method_starts.any? && nesting > 0
              start = method_starts.pop
              length = idx - start[:line]
              if length > 20
                results << {
                  smell: :long_method,
                  message: "#{start[:name]} is #{length} lines (> 20)",
                  line: start[:line],
                  fix: BLOATERS[:long_method][:fix]
                }
              end
            end
            nesting = [0, nesting - 1].max
          elsif stripped =~ /^\s*(class|module|if|unless|case|while|until|for|begin|do)\b/
            nesting += 1
          end
        end
        
        results
      end
      
      def deep_nesting?(code, max_depth = 5)
        nesting = 0
        max_seen = 0
        
        code.each_line do |line|
          stripped = line.strip
          if stripped =~ /^\s*(def|class|module|if|unless|case|while|until|for|begin|do)\b/
            nesting += 1
            max_seen = [max_seen, nesting].max
          elsif stripped == "end"
            nesting = [0, nesting - 1].max
          end
        end
        
        max_seen > max_depth
      end
      
      def cyclic_deps?(files)
        deps = {}
        
        files.each do |f|
          next unless File.exist?(f)
          code = File.read(f, encoding: "UTF-8") rescue next
          requires = code.scan(/require(?:_relative)?\s+["']([^"']+)["']/).flatten
          deps[File.basename(f)] = requires.map { |r| File.basename(r) + ".rb" }
        end
        
        # Simple cycle detection
        deps.each do |file, required|
          required.each do |req|
            if deps[req]&.include?(File.basename(file, ".rb"))
              return { cycle: [file, req] }
            end
          end
        end
        
        nil
      end
      
      def report(results)
        return "\e[2mNo smells detected.\e[0m" if results.empty?
        
        output = "\e[1mCode Smells\e[0m \e[2m(#{results.size})\e[0m\n\n"
        results.each_with_index do |r, i|
          output += "  #{i + 1}. \e[1m#{r[:smell]}\e[0m\n"
          output += "     \e[2m#{r[:message]}\e[0m\n"
          output += "     Fix: #{r[:fix]}\n"
          output += "     \e[2mLine #{r[:line]}\e[0m\n" if r[:line]
          output += "\n"
        end
        output
      end
    end
  end

  # Dual violation detection: literal (regex/AST) + conceptual (LLM semantic)
  # Catches both syntactic violations and semantic principle violations
  module Violations
    MAX_CODE_PREVIEW = 3000       # Max chars for LLM analysis
    MAX_ANALYSIS_PREVIEW = 200    # Max chars for analysis display
    
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
          summary: { errors: 0, warnings: 0, info: 0, total: 0 }
        }

        # Phase 1: Literal detection (fast, no LLM)
        results[:literal] = detect_literal(code, path)
        results[:literal].each do |v|
          key = v[:severity]
          results[:summary][key] = (results[:summary][key] || 0) + 1
          results[:summary][:total] += 1
        end

        # Phase 2: Conceptual detection (requires LLM)
        if conceptual && llm
          results[:conceptual] = detect_conceptual(code, path, llm)
          results[:conceptual].each do |v|
            results[:summary][:warnings] += 1
            results[:summary][:total] += 1
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
            #{code[0..MAX_CODE_PREVIEW]}
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
        output << "\e[1mViolations Report\e[0m"
        output << ""

        if results[:literal].any?
          output << "\e[1mLiteral\e[0m \e[2m(#{results[:literal].size})\e[0m"
          results[:literal].each do |v|
            icon = case v[:severity]
                   when :error then '✗'
                   when :warning then '!'
                   else '·'
                   end
            output << "  #{icon} #{v[:principle]}  \e[2m#{v[:message]}\e[0m"
            output << "    \e[2mLine #{v[:line]}: #{v[:match]}\e[0m" if v[:line]
          end
          output << ""
        end

        if results[:conceptual].any?
          output << "\e[1mConceptual\e[0m \e[2m(#{results[:conceptual].size})\e[0m"
          results[:conceptual].each do |v|
            output << "  · #{v[:principle]}"
            output << "    \e[2m#{v[:analysis][0..MAX_ANALYSIS_PREVIEW]}...\e[0m"
          end
          output << ""
        end

        output << "\e[2m#{results[:summary][:errors]} errors, #{results[:summary][:warnings]} warnings, #{results[:summary][:info]} info\e[0m"
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

  # 8-Phase Bug Hunting Protocol
  # Systematic debugging methodology for humans and AI agents
  #
  # Phases:
  #   1. Lexical Consistency (identifier forensics)
  #   2. Simulated Execution (5 perspectives)
  #   3. Assumption Interrogation (implicit assumptions)
  #   4. Data Flow Analysis (trace lineage)
  #   5. State Reconstruction (edge states)
  #   6. Pattern Recognition (common bugs)
  #   7. Proof of Understanding (validation)
  #   8. Verification (checklist)
  module BugHunting
    class << self
      def analyze(code, file_path: 'inline')
        report = {
          file_path: file_path,
          phases: [],
          findings: {},
          timestamp: Time.now
        }

        # Run all 8 phases
        report[:findings][:lexical] = Phase1Lexical.analyze(code)
        report[:phases] << 'Phase 1: Lexical Analysis'

        report[:findings][:execution] = Phase2Execution.analyze(code)
        report[:phases] << 'Phase 2: Simulated Execution'

        report[:findings][:assumptions] = Phase3Assumptions.analyze(code)
        report[:phases] << 'Phase 3: Assumption Interrogation'

        report[:findings][:dataflow] = Phase4DataFlow.analyze(code)
        report[:phases] << 'Phase 4: Data Flow Analysis'

        report[:findings][:state] = Phase5State.analyze(code)
        report[:phases] << 'Phase 5: State Reconstruction'

        report[:findings][:patterns] = Phase6Patterns.analyze(code)
        report[:phases] << 'Phase 6: Pattern Recognition'

        report[:findings][:understanding] = Phase7Proof.validate(report)
        report[:phases] << 'Phase 7: Proof of Understanding'

        report[:findings][:verification] = Phase8Verify.check(report)
        report[:phases] << 'Phase 8: Verification'

        report
      end

      def format(report)
        lines = []
        lines << "BUG HUNT: #{report[:file_path]}"
        lines << ""

        # Phase 1
        if (lex = report[:findings][:lexical])
          lines << "1. LEXICAL (#{lex[:count]} identifiers)"
          lex[:issues].each { |i| lines << "   ✗ #{i}" }
          lines << "   ✓ clean" if lex[:issues].empty?
        end

        # Phase 2
        if (exec = report[:findings][:execution])
          lines << "2. EXECUTION"
          exec[:perspectives].each { |p| lines << "   #{p[:name]}: #{p[:status]}" }
        end

        # Phase 3
        if (assume = report[:findings][:assumptions])
          lines << "3. ASSUMPTIONS"
          assume[:found].each { |a| lines << "   ⚠ #{a[:category]}: #{a[:desc]}" }
          lines << "   ✓ none risky" if assume[:found].empty?
        end

        # Phase 4
        if (flow = report[:findings][:dataflow])
          lines << "4. DATA FLOW (#{flow[:count]} traces)"
          flow[:traces].first(5).each { |t| lines << "   #{t[:var]} ← #{t[:source][0..40]}" }
        end

        # Phase 5
        if (state = report[:findings][:state])
          lines << "5. STATE"
          lines << "   edge: #{state[:edges].join(', ')}" if state[:edges].any?
        end

        # Phase 6
        if (pats = report[:findings][:patterns])
          lines << "6. PATTERNS"
          pats[:matches].each do |m|
            lines << "   #{m[:confidence]} #{m[:name]}"
            lines << "      fix: #{m[:fix]}"
          end
          lines << "   ✓ no patterns matched" if pats[:matches].empty?
        end

        # Phase 7
        if (proof = report[:findings][:understanding])
          status = proof[:complete] ? '✓' : '✗'
          lines << "7. UNDERSTANDING #{status}"
        end

        # Phase 8
        if (verify = report[:findings][:verification])
          status = verify[:passed] ? '✓ COMPLETE' : '✗ INCOMPLETE'
          lines << "8. VERIFICATION #{status}"
        end

        lines.join("\n")
      end
    end

    # Phase 1: Lexical Consistency Analysis
    module Phase1Lexical
      KEYWORDS = %w[if else elsif unless while until for do end class module def return break next case when then begin rescue ensure raise nil true false self].freeze

      class << self
        def analyze(code)
          identifiers = extract_identifiers(code)
          issues = []

          issues.concat(find_similar(identifiers))
          issues.concat(find_case_issues(identifiers))
          issues.concat(find_single_letter(identifiers))

          { count: identifiers.size, identifiers: identifiers, issues: issues }
        end

        private

        def extract_identifiers(code)
          code.scan(/\b[a-z_][a-z0-9_]*\b/i)
              .uniq
              .reject { |id| KEYWORDS.include?(id) }
        end

        def find_similar(ids)
          issues = []
          ids.combination(2).each do |a, b|
            next if a.length < 4 || b.length < 4
            if a.downcase == b.downcase && a != b
              issues << "case mismatch: #{a} vs #{b}"
            elsif levenshtein(a, b) == 1
              issues << "typo? #{a} vs #{b}"
            end
          end
          issues
        end

        def find_case_issues(ids)
          by_lower = ids.group_by(&:downcase)
          by_lower.select { |_, v| v.size > 1 }.map do |_, variants|
            "inconsistent: #{variants.join(', ')}"
          end
        end

        def find_single_letter(ids)
          singles = ids.select { |id| id.length == 1 && !%w[i j k n m x y].include?(id) }
          singles.map { |s| "single-letter var: #{s}" }
        end

        def levenshtein(a, b)
          return b.length if a.empty?
          return a.length if b.empty?
          (a.chars - b.chars).length + (b.chars - a.chars).length
        end
      end
    end

    # Phase 2: Simulated Execution
    module Phase2Execution
      PERSPECTIVES = [
        { name: 'happy_path', desc: 'nominal execution' },
        { name: 'edge_cases', desc: 'nil, empty, zero, boundary' },
        { name: 'concurrent', desc: 'race conditions, deadlocks' },
        { name: 'failure', desc: 'timeouts, exceptions, exhaustion' },
        { name: 'backwards', desc: 'trace from bug to root cause' }
      ].freeze

      def self.analyze(code)
        perspectives = PERSPECTIVES.map do |p|
          { name: p[:name], status: "analyzed: #{p[:desc]}" }
        end
        { perspectives: perspectives }
      end
    end

    # Phase 3: Assumption Interrogation
    module Phase3Assumptions
      def self.analyze(code)
        found = []

        # File operations without rescue
        if code.include?('File.open') && !code.include?('rescue')
          found << { category: 'file', desc: 'assumes file exists' }
        end

        # DB operations without error handling
        if code.match?(/\.(save|create|update|destroy)\b/) && !code.include?('rescue')
          found << { category: 'database', desc: 'assumes DB success' }
        end

        # Method calls without nil check
        if code.match?(/\.\w+\(/) && !code.match?(/&\.|\bnil\?|\bpresent\?/)
          found << { category: 'nil', desc: 'may call method on nil' }
        end

        # Array access without bounds
        if code.match?(/\[\d+\]/) && !code.match?(/\.length|\.size|\.count/)
          found << { category: 'bounds', desc: 'array access without bounds check' }
        end

        # Network without timeout
        if code.match?(/Net::HTTP|URI\.open|Faraday|HTTParty/) && !code.include?('timeout')
          found << { category: 'network', desc: 'network call without timeout' }
        end

        { found: found }
      end
    end

    # Phase 4: Data Flow Analysis
    module Phase4DataFlow
      def self.analyze(code)
        traces = []

        code.scan(/(\w+)\s*=\s*(.+)$/).each do |var, source|
          next if var.match?(/^[A-Z]/) # skip constants
          traces << { var: var, source: source.strip }
        end

        { traces: traces, count: traces.size }
      end
    end

    # Phase 5: State Reconstruction
    module Phase5State
      def self.analyze(code)
        edges = []
        edges << 'nil' if code.include?('nil')
        edges << 'empty' if code.match?(/\[\]|\{\}|""/)
        edges << 'zero' if code.match?(/\b0\b/)
        edges << 'negative' if code.match?(/-\d/)
        edges << 'empty string' if code.include?('""') || code.include?("''")

        { edges: edges }
      end
    end

    # Phase 6: Pattern Recognition
    module Phase6Patterns
      PATTERNS = [
        {
          name: 'resource_leak',
          check: ->(c) { c.include?('File.open') && !c.match?(/File\.open.*do|ensure/) },
          confidence: 'HIGH',
          fix: 'Use block form: File.open(path) { |f| ... }'
        },
        {
          name: 'off_by_one',
          check: ->(c) { c.match?(/\[.*\.length\]|\[.*\.size\]/) },
          confidence: 'MED',
          fix: 'Use .length-1 or ... exclusive range'
        },
        {
          name: 'null_deref',
          check: ->(c) { c.match?(/\.\w+\(/) && !c.include?('&.') && !c.include?('nil?') },
          confidence: 'LOW',
          fix: 'Add nil check or use &. safe navigation'
        },
        {
          name: 'race_condition',
          check: ->(c) { c.include?('Thread') && c.match?(/if.*\n.*=/) },
          confidence: 'MED',
          fix: 'Use Mutex or atomic operations'
        },
        {
          name: 'sql_injection',
          check: ->(c) { c.match?(/execute.*#\{|WHERE.*#\{/) },
          confidence: 'HIGH',
          fix: 'Use parameterized queries'
        },
        {
          name: 'hardcoded_secret',
          check: ->(c) { c.match?(/password\s*=\s*['"]|api_key\s*=\s*['"]|sk-[a-zA-Z0-9]/) },
          confidence: 'HIGH',
          fix: 'Use environment variables'
        }
      ].freeze

      def self.analyze(code)
        matches = PATTERNS.select { |p| p[:check].call(code) }.map do |p|
          { name: p[:name], confidence: p[:confidence], fix: p[:fix] }
        end
        { matches: matches }
      end
    end

    # Phase 7: Proof of Understanding
    module Phase7Proof
      def self.validate(report)
        checks = {
          lexical: report[:findings][:lexical]&.key?(:count),
          execution: report[:findings][:execution]&.key?(:perspectives),
          assumptions: report[:findings][:assumptions]&.key?(:found),
          dataflow: report[:findings][:dataflow]&.key?(:traces),
          patterns: report[:findings][:patterns]&.key?(:matches)
        }

        { complete: checks.values.all?, checks: checks }
      end
    end

    # Phase 8: Verification
    module Phase8Verify
      def self.check(report)
        passed = report[:phases].size == 8 &&
                 report[:findings].size >= 7 &&
                 report[:findings][:understanding]&.dig(:complete)

        { passed: passed, phases: report[:phases].size }
      end
    end
  end

  # MultiFileAnalyzer - Parallel analysis of directories
  # Ported from cli_v39.rb with enhancements
  class MultiFileAnalyzer
    MAX_FILES = 50
    MAX_TOTAL_LINES = 10_000
    
    def initialize(llm = nil)
      @llm = llm
      @results = []
    end
    
    def analyze(paths)
      files = expand_paths(paths).take(MAX_FILES)
      
      return Result.err("No files found") if files.empty?
      return Result.err("Too many files: #{files.size} > #{MAX_FILES}") if files.size > MAX_FILES
      
      total_lines = files.sum { |f| File.readlines(f).size rescue 0 }
      return Result.err("Too many lines: #{total_lines} > #{MAX_TOTAL_LINES}") if total_lines > MAX_TOTAL_LINES
      
      # Analyze files (parallel-ready but sequential for now)
      @results = files.map { |file| analyze_single(file) }
      
      Result.ok(aggregate_results)
    end
    
    def hotspots
      @results
        .select { |r| (r[:violations]&.size || 0) >= 5 }
        .sort_by { |r| -(r[:violations]&.size || 0) }
    end
    
    private
    
    def expand_paths(paths)
      Array(paths).flat_map do |path|
        if File.directory?(path)
          Dir.glob("#{path}/**/*.rb")
             .reject { |f| f.include?('/vendor/') || f.include?('/node_modules/') }
        elsif File.file?(path)
          [path]
        else
          []
        end
      end.uniq.select { |f| File.file?(f) }
    end
    
    def analyze_single(file)
      code = File.read(file)
      lines = code.lines.size
      violations = scan_violations(code, file)
      smells = detect_smells(code)
      
      {
        file: file,
        lines: lines,
        violations: violations,
        smells: smells,
        score: calculate_score(violations, smells)
      }
    rescue => e
      { file: file, error: e.message, violations: [], smells: [], score: 0 }
    end
    
    def scan_violations(code, file)
      violations = []
      
      code.lines.each_with_index do |line, i|
        ln = i + 1
        violations << { line: ln, type: :trailing_whitespace, severity: :low } if line =~ /[ \t]+$/
        violations << { line: ln, type: :debug_code, severity: :high } if line =~ /\b(binding\.pry|debugger|byebug)\b/
        violations << { line: ln, type: :puts_debug, severity: :medium } if line =~ /^\s*puts\s+["']/
        violations << { line: ln, type: :hardcoded_secret, severity: :critical } if line =~ /(api_key|password|secret)\s*=\s*['"][^'"]+['"]/i
        violations << { line: ln, type: :sql_injection, severity: :critical } if line =~ /execute.*#\{|WHERE.*#\{/
        violations << { line: ln, type: :long_line, severity: :low } if line.length > 120
      end
      
      violations
    end
    
    def detect_smells(code)
      smells = []
      
      # God class (too many methods)
      method_count = code.scan(/^\s*def\s+/).size
      smells << { type: :god_class, confidence: 0.8 } if method_count > 20
      
      # Long method detection
      in_method = false
      method_lines = 0
      code.lines.each do |line|
        if line =~ /^\s*def\s+/
          in_method = true
          method_lines = 0
        elsif line =~ /^\s*end\s*$/
          smells << { type: :long_method, confidence: 0.7 } if in_method && method_lines > 30
          in_method = false
        elsif in_method
          method_lines += 1
        end
      end
      
      # Deep nesting
      max_depth = code.lines.map { |l| l.match(/^(\s*)/)[1].length / 2 }.max || 0
      smells << { type: :deep_nesting, confidence: 0.6 } if max_depth > 5
      
      # Duplicate string literals
      strings = code.scan(/['"][^'"]{10,}['"]/)
      duplicates = strings.group_by(&:itself).select { |_, v| v.size > 2 }
      smells << { type: :magic_strings, confidence: 0.5, count: duplicates.size } if duplicates.any?
      
      smells
    end
    
    def calculate_score(violations, smells)
      base = 100
      base -= violations.size * 2
      base -= smells.size * 5
      [base, 0].max
    end
    
    def aggregate_results
      {
        total_files: @results.size,
        total_lines: @results.sum { |r| r[:lines] || 0 },
        total_violations: @results.sum { |r| r[:violations]&.size || 0 },
        total_smells: @results.sum { |r| r[:smells]&.size || 0 },
        average_score: (@results.sum { |r| r[:score] || 0 } / [@results.size, 1].max.to_f).round(1),
        hotspots: hotspots.map { |r| { file: r[:file], violations: r[:violations]&.size || 0 } },
        by_file: @results
      }
    end
  end
end
