# frozen_string_literal: true

module MASTER
  module Review
    module Scanner
      extend self

      # The analysis prompt template - generates categorized opportunities
      OPPORTUNITY_PROMPT = <<~PROMPT
        Analyze this code. Return ONLY a JSON object with four keys:
        architectural, micro, ui_ux, typography.
        Each key maps to an array of objects with: id, description, location, effort, impact.
        id: short_snake_case. description: one sentence. location: file/line or "throughout".
        effort: small/medium/large. impact: low/medium/high.
        5-15 items per category. No markdown, no explanation, just JSON.

        %{code}
      PROMPT

      # Issues found in this codebase that should be auto-detected
      CHECKS = {
        namespace_prefix: {
          pattern: /^(?!.*MASTER::)(DB|LLM|Session|Pipeline)\./,
          message: "Use MASTER:: prefix for module references in bin/ scripts",
          severity: :critical,
        }.freeze,
        symbol_string_fallback: {
          pattern: /\[["'][a-z_]+["']\]\s*\|\|\s*\[:[a-z_]+\]/,
          message: "Mixed string/symbol access - use symbolize_names: true in JSON.parse",
          severity: :major,
        }.freeze,
        dirty_flag_missing: {
          pattern: /\.pop\(|\.shift\(|\.delete|\.clear(?!\s*#.*dirty)/,
          message: "Mutation without @dirty = true - changes won't persist",
          severity: :major,
        }.freeze,
        rescue_without_type: {
          pattern: /rescue\s*$/,
          message: "Bare rescue catches all exceptions - use StandardError",
          severity: :minor,
        }.freeze,
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

          parse_opportunities_json(result.value[:content])
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

        def parse_opportunities_json(response)
          json_str = response[/\{.*\}/m]
          return Result.err("No JSON in response") unless json_str

          data = JSON.parse(json_str, symbolize_names: true)
          categories = { architectural: [], micro: [], ui_ux: [], typography: [] }

          categories.each_key do |cat|
            items = data[cat] || data[cat.to_s] || []
            categories[cat] = items.map do |item|
              {
                id: (item[:id] || "unknown").to_s,
                description: (item[:description] || "").to_s,
                location: (item[:location] || "throughout").to_s,
                effort: (item[:effort] || "medium").to_s,
                impact: (item[:impact] || "medium").to_s,
              }
            end
          end

          Result.ok(categories)
        rescue JSON::ParserError => e
          Result.err("JSON parse failed: #{e.message}")
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
  end
end
