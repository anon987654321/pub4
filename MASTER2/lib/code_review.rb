# frozen_string_literal: true

require 'yaml'

module MASTER
  # CodeReview - Automated checks learned from deep analysis sessions
  # These patterns were discovered through cross-referencing and execution tracing
  module CodeReview
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
  end

  # Code smell detection - complements Violations with structural analysis
  # Merged from smells.rb
  module Smells
    extend self

    def thresholds
      @thresholds ||= begin
        config = load_config
        {
          max_method_lines: config.dig('thresholds', 'method_length') || 20,
          max_file_lines: config.dig('thresholds', 'file_lines') || 300,
          max_parameters: config.dig('thresholds', 'parameter_count') || 4,
          max_nesting: config.dig('thresholds', 'nesting_depth') || 5,
          max_public_methods: config.dig('thresholds', 'class_methods') || 10,
          min_duplicate_count: config.dig('thresholds', 'min_duplicate_count') || 3
        }
      end
    end

    def patterns
      @patterns ||= begin
        config = load_config
        bloaters = config['bloaters'] || default_bloaters
        couplers = config['couplers'] || default_couplers
        dispensables = config['dispensables'] || default_dispensables
        architecture = config['architecture'] || default_architecture
        rails = config['rails_specific'] || {}
        pwa = config['pwa_specific'] || {}
        html_css = config['html_css_quality'] || {}
        
        bloaters.merge(couplers).merge(dispensables).merge(architecture)
                .merge(rails).merge(pwa).merge(html_css)
      end
    end

    class << self
      def all_patterns
        patterns
      end

      def analyze(code, file_path = nil)
        results = []
        lines = code.lines
        t = thresholds
        p = patterns

        results += analyze_ruby_methods(code, lines) if file_path&.end_with?('.rb')

        if lines.size > t[:max_file_lines]
          results << {
            smell: :god_class,
            message: "File has #{lines.size} lines (> #{t[:max_file_lines]})",
            fix: p.dig(:god_class, :fix) || p.dig(:god_class, 'fix') || 'Extract class'
          }
        end

        code.scan(/def\s+\w+\(([^)]+)\)/) do |params|
          count = params[0].split(',').size
          if count > t[:max_parameters]
            results << {
              smell: :long_parameter_list,
              message: "Method has #{count} parameters (> #{t[:max_parameters]})",
              fix: p.dig(:long_parameter_list, :fix) || p.dig(:long_parameter_list, 'fix') || 'Parameter object'
            }
          end
        end

        code.scan(/\w+(?:\.\w+){3,}/) do |chain|
          results << {
            smell: :message_chains,
            message: "Long chain: #{chain[0..40]}...",
            fix: p.dig(:message_chains, :fix) || p.dig(:message_chains, 'fix') || 'Hide delegate'
          }
        end

        strings = code.scan(/"[^"]{10,}"/).flatten
        dupes = strings.group_by(&:itself).select { |_, v| v.size >= t[:min_duplicate_count] }
        dupes.each do |str, occurrences|
          results << {
            smell: :primitive_obsession,
            message: "String #{str[0..30]}... repeated #{occurrences.size}x",
            fix: 'Extract to constant'
          }
        end

        results
      end

      def analyze_ruby_methods(code, lines)
        results = []
        method_starts = []
        nesting = 0
        t = thresholds
        p = patterns

        lines.each_with_index do |line, idx|
          stripped = line.strip

          if stripped =~ /^\s*def\s+/
            method_starts << { line: idx + 1, nesting: nesting, name: stripped }
            nesting += 1
          elsif stripped == 'end'
            if method_starts.any? && nesting.positive?
              start = method_starts.pop
              length = idx - start[:line]
              if length > t[:max_method_lines]
                results << {
                  smell: :long_method,
                  message: "#{start[:name]} is #{length} lines (> #{t[:max_method_lines]})",
                  line: start[:line],
                  fix: p.dig(:long_method, :fix) || p.dig(:long_method, 'fix') || 'Extract method'
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

      def deep_nesting?(code, max_depth = nil)
        max_depth ||= thresholds[:max_nesting]
        nesting = 0
        max_seen = 0

        code.each_line do |line|
          stripped = line.strip
          if stripped =~ /^\s*(def|class|module|if|unless|case|while|until|for|begin|do)\b/
            nesting += 1
            max_seen = [max_seen, nesting].max
          elsif stripped == 'end'
            nesting = [0, nesting - 1].max
          end
        end

        max_seen > max_depth
      end

      def cyclic_deps?(files)
        deps = {}

        files.each do |f|
          next unless File.exist?(f)

          code = File.read(f, encoding: 'UTF-8') rescue next
          requires = code.scan(/require(?:_relative)?\s+["']([^"']+)["']/).flatten
          deps[File.basename(f)] = requires.map { |r| "#{File.basename(r)}.rb" }
        end

        deps.each do |file, required|
          required.each do |req|
            return { cycle: [file, req] } if deps[req]&.include?(File.basename(file, '.rb'))
          end
        end

        nil
      end

      def report(results)
        return 'No smells detected.' if results.empty?

        output = ["Code Smells (#{results.size})", '']
        results.each_with_index do |r, i|
          output << "  #{i + 1}. #{r[:smell]}"
          output << "     #{r[:message]}"
          output << "     Fix: #{r[:fix]}"
          output << "     Line #{r[:line]}" if r[:line]
          output << ''
        end
        output.join("\n")
      end

      private

      def load_config
        path = File.join(MASTER.root, 'data', 'smells.yml')
        YAML.safe_load_file(path, permitted_classes: [Symbol])
      rescue Errno::ENOENT
        {}
      end

      def default_bloaters
        t = thresholds
        {
          'long_method' => { 'check' => "> #{t[:max_method_lines]} lines", 'fix' => 'Extract method' },
          'god_class' => { 'check' => "> #{t[:max_file_lines]} lines", 'fix' => 'Extract class' },
          'primitive_obsession' => { 'check' => 'Repeated primitive patterns', 'fix' => 'Introduce value object' },
          'long_parameter_list' => { 'check' => "> #{t[:max_parameters]} parameters", 'fix' => 'Parameter object' }
        }
      end

      def default_couplers
        {
          'feature_envy' => { 'check' => 'Method uses other class more than self', 'fix' => 'Move method' },
          'inappropriate_intimacy' => { 'check' => 'Classes know too much', 'fix' => 'Extract class' },
          'message_chains' => { 'check' => 'Long chains like a.b.c.d', 'fix' => 'Hide delegate' }
        }
      end

      def default_dispensables
        {
          'dead_code' => { 'check' => 'Unreachable or unused code', 'fix' => 'Delete it' },
          'lazy_class' => { 'check' => 'Class does almost nothing', 'fix' => 'Inline or merge' },
          'duplicate_code' => { 'check' => 'Same logic in multiple places', 'fix' => 'Extract method/class' }
        }
      end

      def default_architecture
        {
          'cyclic_dependency' => { 'check' => 'A requires B requires A', 'fix' => 'Dependency inversion' },
          'scattered_functionality' => { 'check' => 'Related code in many files', 'fix' => 'Colocate' }
        }
      end
    end
  end

  # Dual violation detection: literal (regex/AST) + conceptual (LLM semantic)
  # Catches both syntactic violations and semantic principle violations
  # Merged from violations.rb
  module Violations
    extend self

    MAX_CODE_PREVIEW = 3000
    MAX_ANALYSIS_PREVIEW = 200

    # Literal patterns for fast detection (no LLM needed)
    LITERAL_PATTERNS = {
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
      magic_number: {
        pattern: /[^0-9a-z_]([2-9]\d{2,}|[1-9]\d{3,})[^0-9a-z_]/i,
        principle: 'DRY',
        message: 'Magic number detected (should be named constant)',
        severity: :info
      },
      commented_code: {
        pattern: /^\s*#\s*(def |class |module |if |unless |case |while )/,
        principle: 'YAGNI',
        message: 'Commented out code detected',
        severity: :warning
      },
      method_chain: {
        pattern: /\w+\.\w+\.\w+\.\w+/,
        principle: 'Law of Demeter',
        message: 'Long method chain (train wreck)',
        severity: :warning
      },
      bare_rescue: {
        pattern: /rescue\s*$/,
        principle: 'Fail Fast',
        message: 'Bare rescue swallows errors silently',
        severity: :warning
      },
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
      short_variable: {
        pattern: /\b([a-z])\s*=/,
        principle: 'Meaningful Names',
        message: 'Single letter variable name',
        severity: :info
      },
      many_parameters: {
        pattern: /def\s+\w+\s*\(([^)]*,){4,}[^)]*\)/,
        principle: 'Few Arguments',
        message: 'Method has too many parameters (>4)',
        severity: :warning
      },
      string_slice_magic: {
        pattern: /\[0\.\.\d{3,}\]/,
        principle: 'DRY',
        message: 'Magic number in string slice (use constant)',
        severity: :info
      }
    }.freeze

    # Conceptual checks for LLM semantic analysis
    CONCEPTUAL_CHECKS = {
      kiss: {
        prompt: 'Is this code unnecessarily complex? Could it be simpler?',
        examples: ['Metaprogramming when simple method works', 'Over-abstracted hierarchies']
      },
      dry: {
        prompt: 'Is there duplicated logic that should be extracted?',
        examples: ['Similar error handling repeated', 'Same validation in multiple places']
      },
      yagni: {
        prompt: 'Is there code built for hypothetical future requirements?',
        examples: ['Unused parameters "for future use"', 'Abstract factories with single impl']
      },
      single_responsibility: {
        prompt: 'Does this class/module have more than one reason to change?',
        examples: ['Class handling business logic and persistence', 'Method doing calculation and formatting']
      },
      law_of_demeter: {
        prompt: 'Does the code reach through objects to access internals?',
        examples: ['user.account.subscription.plan.price', 'Deep nested hash access']
      },
      fail_fast: {
        prompt: 'Does the code validate inputs early or wait until problems propagate?',
        examples: ['Processing continues after invalid state', 'Nil checks at end instead of beginning']
      }
    }.freeze

    class << self
      def analyze(code, path: nil, llm: nil, conceptual: true)
        results = {
          literal: [],
          conceptual: [],
          summary: { errors: 0, warnings: 0, info: 0, total: 0 }
        }

        results[:literal] = detect_literal(code, path)
        results[:literal].each do |v|
          key = v[:severity]
          results[:summary][key] = (results[:summary][key] || 0) + 1
          results[:summary][:total] += 1
        end

        if conceptual && llm
          results[:conceptual] = detect_conceptual(code, path, llm)
          results[:conceptual].each do
            results[:summary][:warnings] += 1
            results[:summary][:total] += 1
          end
        end

        results
      end

      def detect_literal(code, _path = nil)
        violations = []
        lines = code.lines

        LITERAL_PATTERNS.each do |name, config|
          next unless config[:pattern]

          lines.each_with_index do |line, idx|
            next unless line.match?(config[:pattern])

            violations << {
              type: :literal,
              name: name,
              principle: config[:principle],
              message: config[:message],
              severity: config[:severity],
              line: idx + 1,
              match: line.strip[0..50]
            }
          end
        end

        violations += check_method_lengths(lines)
        violations += check_require_count(code)
        violations += check_repeated_strings(code)
        violations
      end

      def detect_conceptual(code, _path, llm)
        violations = []
        checks_to_run = CONCEPTUAL_CHECKS.keys.sample(3)

        checks_to_run.each do |principle|
          config = CONCEPTUAL_CHECKS[principle]

          prompt = <<~PROMPT
            Analyze this Ruby code for #{principle.to_s.upcase.tr('_', ' ')} violations.
            #{config[:prompt]}
            Examples: #{config[:examples].join(', ')}

            CODE:
            ```ruby
            #{code[0..MAX_CODE_PREVIEW]}
            ```

            If violations exist, list them with line numbers.
            If clean, say "No violations found."
          PROMPT

          result = llm.ask(prompt, tier: :cheap)
          next unless result.ok?

          response = result.value.to_s.downcase
          next if response.include?('no violations') || response.include?('code is clean')

          violations << {
            type: :conceptual,
            principle: principle.to_s.tr('_', ' ').upcase,
            analysis: result.value[0..MAX_ANALYSIS_PREVIEW],
            severity: :warning
          }
        end

        violations
      end

      def quick_scan(path, llm: nil)
        return { error: 'File not found' } unless File.exist?(path)

        code = File.read(path)
        analyze(code, path: path, llm: llm, conceptual: !llm.nil?)
      end

      def check_literal(code)
        detect_literal(code, nil)
      end

      def report(results)
        output = []
        output << "Violations Report"
        output << ""

        if results[:literal].any?
          output << "Literal (#{results[:literal].size})"
          results[:literal].each do |v|
            icon = case v[:severity]
                   when :error then '✗'
                   when :warning then '!'
                   else '·'
                   end
            output << "  #{icon} #{v[:principle]}  #{v[:message]}"
            output << "    Line #{v[:line]}: #{v[:match]}" if v[:line]
          end
        end

        if results[:conceptual].any?
          output << ""
          output << "Conceptual (#{results[:conceptual].size})"
          results[:conceptual].each do |v|
            output << "  · #{v[:principle]}"
            output << "    #{v[:analysis]}..."
          end
        end

        output << ""
        output << "#{results[:summary][:errors]} errors, #{results[:summary][:warnings]} warnings, #{results[:summary][:info]} info"
        output.join("\n")
      end

      private

      def check_method_lengths(lines)
        violations = []
        method_start = nil
        method_name = nil

        lines.each_with_index do |line, idx|
          if line =~ /^\s*def\s+(\w+)/
            method_start = idx
            method_name = ::Regexp.last_match(1)
          elsif method_start && line.strip == 'end'
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
    end
  end

  # 8-Phase Bug Hunting Protocol
  # Systematic debugging methodology
  # Merged from bug_hunting.rb
  module BugHunting
    extend self

    # Diagnostic escalation levels (cheap to expensive)
    ESCALATION_LEVELS = %i[syntax logic history llm].freeze

    class << self
      # Hunt for bugs with automatic escalation
      def hunt(error_or_file, level: :auto)
        if level == :auto
          escalate(error_or_file)
        else
          send(:"level_#{level}", error_or_file)
        end
      end

      def analyze(code, file_path: 'inline')
        report = {
          file_path: file_path,
          phases: [],
          findings: {},
          timestamp: Time.now
        }

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
        lines = ["BUG HUNT: #{report[:file_path]}", '']

        if (lex = report[:findings][:lexical])
          lines << "1. LEXICAL (#{lex[:count]} identifiers)"
          lex[:issues].each { |i| lines << "   ✗ #{i}" }
          lines << '   ✓ clean' if lex[:issues].empty?
        end

        if (exec = report[:findings][:execution])
          lines << '2. EXECUTION'
          exec[:perspectives].each { |p| lines << "   #{p[:name]}: #{p[:status]}" }
        end

        if (assume = report[:findings][:assumptions])
          lines << '3. ASSUMPTIONS'
          assume[:found].each { |a| lines << "   ⚠ #{a[:category]}: #{a[:desc]}" }
          lines << '   ✓ none risky' if assume[:found].empty?
        end

        if (flow = report[:findings][:dataflow])
          lines << "4. DATA FLOW (#{flow[:count]} traces)"
          flow[:traces].first(5).each { |t| lines << "   #{t[:var]} ← #{t[:source][0..40]}" }
        end

        if (state = report[:findings][:state])
          lines << '5. STATE'
          lines << "   edge: #{state[:edges].join(', ')}" if state[:edges].any?
        end

        if (pats = report[:findings][:patterns])
          lines << '6. PATTERNS'
          pats[:matches].each do |m|
            lines << "   #{m[:confidence]} #{m[:name]}"
            lines << "      fix: #{m[:fix]}"
          end
          lines << '   ✓ no patterns matched' if pats[:matches].empty?
        end

        if (proof = report[:findings][:understanding])
          status = proof[:complete] ? '✓' : '✗'
          lines << "7. UNDERSTANDING #{status}"
        end

        if (verify = report[:findings][:verification])
          status = verify[:passed] ? '✓ COMPLETE' : '✗ INCOMPLETE'
          lines << "8. VERIFICATION #{status}"
        end

        lines.join("\n")
      end

      # Escalation strategy - try cheap fixes before expensive LLM
      private

      def escalate(target)
        puts UI.dim("🔍 Diagnostic escalation...")

        # Level 1: Syntax (2 sec, $0)
        result = level_syntax(target)
        return result if result[:fixed]

        # Level 2: Logic (10 sec, $0)
        result = level_logic(target)
        return result if result[:fixed]

        # Level 3: History (30 sec, $0)
        result = level_history(target)
        return result if result[:fixed]

        # Level 4: LLM (60 sec, $0.10-0.50)
        level_llm(target)
      end

      def level_syntax(target)
        puts UI.dim("  Level 1: Syntax check...")
        
        if target.end_with?('.rb')
          output = `ruby -c #{target} 2>&1`
          if $?.success?
            { level: :syntax, fixed: false, message: "No syntax errors" }
          else
            { level: :syntax, fixed: true, error: output, fix: "Run rubocop -a #{target}" }
          end
        elsif target.end_with?('.sh')
          output = `zsh -n #{target} 2>&1`
          { level: :syntax, fixed: !$?.success?, error: output }
        else
          { level: :syntax, fixed: false }
        end
      end

      def level_logic(target)
        puts UI.dim("  Level 2: Logic check (tests)...")
        
        test_file = target.sub('/lib/', '/test/').sub('.rb', '_test.rb')
        if File.exist?(test_file)
          output = `ruby #{test_file} 2>&1`
          if $?.success?
            { level: :logic, fixed: false, message: "Tests pass" }
          else
            { level: :logic, fixed: true, error: output, fix: "Check test output above" }
          end
        else
          { level: :logic, fixed: false, message: "No tests found" }
        end
      end

      def level_history(target)
        puts UI.dim("  Level 3: Git history...")
        
        if system("git rev-parse --git-dir > /dev/null 2>&1")
          # Check if file was recently modified
          log = `git log --oneline -5 -- #{target}`.strip
          if log.empty?
            { level: :history, fixed: false, message: "No recent changes" }
          else
            { level: :history, fixed: false, history: log, suggestion: "Try: git log --patch -- #{target}" }
          end
        else
          { level: :history, fixed: false, message: "Not a git repo" }
        end
      end

      def level_llm(target)
        puts UI.dim("  Level 4: LLM analysis (costs $$$)...")
        
        # Fall back to existing analyze method
        if File.exist?(target)
          code = File.read(target)
          report = analyze(code, file_path: target)
          { level: :llm, fixed: false, report: report }
        else
          { level: :llm, fixed: false, error: "File not found: #{target}" }
        end
      end

      public
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
          code.scan(/\b[a-z_][a-z0-9_]*\b/i).uniq.reject { |id| KEYWORDS.include?(id) }
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
          by_lower.select { |_, v| v.size > 1 }.map { |_, variants| "inconsistent: #{variants.join(', ')}" }
        end

        def find_single_letter(ids)
          singles = ids.select { |id| id.length == 1 && !%w[i j k n m x y].include?(id) }
          singles.map { |s| "single-letter var: #{s}" }
        end

        def levenshtein(a, b)
          return b.length if a.empty?
          return a.length if b.empty?

          # Wagner-Fischer dynamic programming algorithm
          matrix = Array.new(a.length + 1) { Array.new(b.length + 1) }
          
          (0..a.length).each { |i| matrix[i][0] = i }
          (0..b.length).each { |j| matrix[0][j] = j }
          
          (1..a.length).each do |i|
            (1..b.length).each do |j|
              cost = a[i - 1] == b[j - 1] ? 0 : 1
              matrix[i][j] = [
                matrix[i - 1][j] + 1,      # deletion
                matrix[i][j - 1] + 1,      # insertion
                matrix[i - 1][j - 1] + cost # substitution
              ].min
            end
          end
          
          matrix[a.length][b.length]
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

      def self.analyze(_code)
        perspectives = PERSPECTIVES.map { |p| { name: p[:name], status: "analyzed: #{p[:desc]}" } }
        { perspectives: perspectives }
      end
    end

    # Phase 3: Assumption Interrogation
    module Phase3Assumptions
      def self.analyze(code)
        found = []

        if code.include?('File.open') && !code.include?('rescue')
          found << { category: 'file', desc: 'assumes file exists' }
        end

        if code.match?(/\.(save|create|update|destroy)\b/) && !code.include?('rescue')
          found << { category: 'database', desc: 'assumes DB success' }
        end

        if code.match?(/\.\w+\(/) && !code.match?(/&\.|\bnil\?|\bpresent\?/)
          found << { category: 'nil', desc: 'may call method on nil' }
        end

        if code.match?(/\[\d+\]/) && !code.match?(/\.length|\.size|\.count/)
          found << { category: 'bounds', desc: 'array access without bounds check' }
        end

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
          next if var.match?(/^[A-Z]/)

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
        { name: 'resource_leak', check: ->(c) { c.include?('File.open') && !c.match?(/File\.open.*do|ensure/) }, confidence: 'HIGH', fix: 'Use block form: File.open(path) { |f| ... }' },
        { name: 'off_by_one', check: ->(c) { c.match?(/\[.*\.length\]|\[.*\.size\]/) }, confidence: 'MED', fix: 'Use .length-1 or ... exclusive range' },
        { name: 'null_deref', check: ->(c) { c.match?(/\.\w+\(/) && !c.include?('&.') && !c.include?('nil?') }, confidence: 'LOW', fix: 'Add nil check or use &. safe navigation' },
        { name: 'race_condition', check: ->(c) { c.include?('Thread') && c.match?(/if.*\n.*=/) }, confidence: 'MED', fix: 'Use Mutex or atomic operations' },
        { name: 'sql_injection', check: ->(c) { c.match?(/execute.*#\{|WHERE.*#\{/) }, confidence: 'HIGH', fix: 'Use parameterized queries' },
        { name: 'hardcoded_secret', check: ->(c) { c.match?(/password\s*=\s*['"]|api_key\s*=\s*['"]|sk-[a-zA-Z0-9]/) }, confidence: 'HIGH', fix: 'Use environment variables' }
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

  # Prescan - Mandatory situational awareness before touching code
  # Ported from MASTER v1 cli.rb prescan ritual
  # Merged from prescan.rb
  module Prescan
    extend self

    def run(path = MASTER.root)
      puts UI.bold("\n🔍 Prescan")
      puts UI.dim("Understanding codebase state before proceeding...\n")

      results = {
        tree: show_tree(path),
        sprawl: detect_sprawl(path),
        git_status: check_git_status(path),
        recent_commits: show_recent_commits(path)
      }

      warn_if_issues(results)
      results
    end

    private

    def show_tree(path)
      puts UI.dim("Structure:")
      
      if system("which tree > /dev/null 2>&1")
        system("tree -L 3 -I 'node_modules|.git|tmp|vendor' #{path}")
        true
      else
        # Fallback: simple directory listing
        puts `find #{path} -maxdepth 3 -type d | head -20`
        false
      end
    end

    def detect_sprawl(path)
      large_files = []
      
      Dir.glob(File.join(path, "**", "*.rb")).each do |file|
        lines = File.readlines(file).size
        if lines > 500
          large_files << { file: file, lines: lines }
        end
      end

      if large_files.any?
        puts UI.yellow("\n⚠️  Sprawl detected (#{large_files.size} files > 500 lines):")
        large_files.first(5).each do |f|
          puts "  #{File.basename(f[:file])}: #{f[:lines]} lines"
        end
      end

      large_files
    end

    def check_git_status(path)
      return nil unless system("git -C #{path} rev-parse --git-dir > /dev/null 2>&1")

      status = `git -C #{path} status --porcelain`.strip
      
      if status.empty?
        puts UI.green("\n✓ Git: Clean working tree")
      else
        puts UI.yellow("\n⚠️  Git: Uncommitted changes:")
        puts status.lines.first(5).map { |l| "  #{l}" }
      end

      status
    end

    def show_recent_commits(path)
      return nil unless system("git -C #{path} rev-parse --git-dir > /dev/null 2>&1")

      puts UI.dim("\nRecent commits:")
      system("git -C #{path} log --oneline --decorate -5")
      
      true
    end

    def warn_if_issues(results)
      warnings = []
      
      warnings << "Large files detected" if results[:sprawl]&.any?
      warnings << "Uncommitted changes" if results[:git_status] && !results[:git_status].empty?

      if warnings.any?
        puts UI.yellow("\n⚠️  Issues: #{warnings.join(', ')}")
        puts UI.dim("Consider addressing these before proceeding.\n")
      else
        puts UI.green("\n✓ All clear\n")
      end
    end
  end

  # FileHygiene - Clean up file formatting issues
  # Merged from file_hygiene.rb
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

  # RubocopDetector - Integration with RuboCop for style violation detection
  # Provides programmatic access to RuboCop's linting capabilities
  # Merged from rubocop_detector.rb
  class RubocopDetector
    # Scan file for RuboCop violations
    # @param file_path [String] Path to Ruby file to scan
    # @return [Result] Ok with violations array, or Err with error message
    def self.scan(file_path)
      return Result.err("RuboCop not installed") unless installed?
      return Result.err("File not found: #{file_path}") unless File.exist?(file_path)

      begin
        require 'rubocop'
        
        # Configure RuboCop
        config_store = RuboCop::ConfigStore.new
        options = {
          formatters: [],
          force_exclusion: false,
        }
        
        # Create runner and process file
        runner = RuboCop::Runner.new(options, config_store)
        results = []
        
        # Temporarily capture offenses
        original_stdout = $stdout
        $stdout = StringIO.new
        
        begin
          # Run RuboCop on the file
          runner.run([file_path])
          
          # Access offenses through the runner's result cache
          if runner.instance_variable_defined?(:@result_cache)
            cache = runner.instance_variable_get(:@result_cache)
            if cache && cache[file_path]
              cache[file_path].offenses.each do |offense|
                results << format_offense(offense)
              end
            end
          end
        ensure
          $stdout = original_stdout
        end
        
        Result.ok(violations: results, file: file_path, count: results.size)
      rescue LoadError
        Result.err("RuboCop gem not available")
      rescue StandardError => e
        Result.err("RuboCop scan failed: #{e.message}")
      end
    end

    # Scan multiple files
    # @param file_paths [Array<String>] Paths to Ruby files
    # @return [Result] Ok with aggregated results, or Err
    def self.scan_multiple(file_paths)
      return Result.err("RuboCop not installed") unless installed?
      
      all_results = []
      file_paths.each do |path|
        result = scan(path)
        if result.ok?
          all_results << result.value
        else
          return result  # Early exit on error
        end
      end
      
      total_violations = all_results.sum { |r| r[:count] }
      Result.ok(
        files: all_results,
        total_violations: total_violations,
        files_scanned: file_paths.size
      )
    end

    # Check if RuboCop is available
    # @return [Boolean] true if RuboCop gem is installed
    def self.installed?
      require 'rubocop'
      true
    rescue LoadError
      false
    end

    # Get RuboCop version if installed
    # @return [String, nil] Version string or nil if not installed
    def self.version
      return nil unless installed?
      require 'rubocop'
      RuboCop::Version.version
    end

    private

    # Format RuboCop offense into consistent hash
    # @param offense [RuboCop::Cop::Offense] RuboCop offense object
    # @return [Hash] Formatted offense data
    def self.format_offense(offense)
      {
        line: offense.line,
        column: offense.column,
        severity: offense.severity.name,
        message: offense.message,
        cop_name: offense.cop_name,
        correctable: offense.correctable?,
        corrected: offense.corrected?,
      }
    end
  end
end
