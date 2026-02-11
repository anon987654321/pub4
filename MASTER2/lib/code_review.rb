# frozen_string_literal: true

require 'yaml'  # Used by Smells module

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

    class RubocopDetector
      def self.scan(file_path)
        return Result.err("RuboCop not installed") unless installed?
        return Result.err("File not found: #{file_path}") unless File.exist?(file_path)

        begin
          require 'rubocop'
          
          config_store = RuboCop::ConfigStore.new
          options = {
            formatters: [],
            force_exclusion: false,
          }
          
          runner = RuboCop::Runner.new(options, config_store)
          results = []
          
          original_stdout = $stdout
          $stdout = StringIO.new
          
          begin
            runner.run([file_path])
            
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

      def self.scan_multiple(file_paths)
        return Result.err("RuboCop not installed") unless installed?
        
        all_results = []
        file_paths.each do |path|
          result = scan(path)
          if result.ok?
            all_results << result.value
          else
            return result
          end
        end
        
        total_violations = all_results.sum { |r| r[:count] }
        Result.ok(
          files: all_results,
          total_violations: total_violations,
          files_scanned: file_paths.size
        )
      end

      def self.installed?
        require 'rubocop'
        true
      rescue LoadError
        false
      end

      def self.version
        return nil unless installed?
        require 'rubocop'
        RuboCop::Version.version
      end

      private

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

  # Backward compatibility aliases
  Smells = CodeReview::Smells
  RubocopDetector = CodeReview::RubocopDetector
end
