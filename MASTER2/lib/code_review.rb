# frozen_string_literal: true

# Load all code review sub-modules
require_relative "code_review/violations"
require_relative "code_review/smells"
require_relative "code_review/bug_hunting"
require_relative "code_review/engine"
require_relative "code_review/llm_friendly"
require_relative "code_review/audit"
require_relative "code_review/cross_ref"

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
