# frozen_string_literal: true

require_relative "analyzers"

module MASTER
  # Dual violation detection: literal (regex/AST) + conceptual (LLM semantic)
  # Catches both syntactic violations and semantic principle violations
  module Violations
    MAX_CODE_PREVIEW = 3000
    MAX_ANALYSIS_PREVIEW = 200

    # Looks up enrichment data from MASTER1-ported principles.yml.
    module PrinciplesDb
      PRINCIPLES_FILE = Paths.data_file("principles.yml")

      # Returns { smell:, fix: } for the closest matching anti-pattern, or nil.
      def self.enrich(principle_name)
        @data ||= begin
          YAML.safe_load_file(PRINCIPLES_FILE)["principles"]
        rescue StandardError
          {}
        end
        slug = principle_name.to_s.downcase.gsub(/[^a-z0-9]/, "")
        entry = @data.values.find do |p|
          pslug = p["name"].to_s.downcase.gsub(/[^a-z0-9]/, "")
          pslug.include?(slug) || slug.include?(pslug[0, 4])
        end
        return nil unless entry

        ap = Array(entry["anti_patterns"]).first
        return nil unless ap

        { smell: ap["smell"], fix: ap["fix"], principle_full: entry["name"] }
      end
    end

    # Literal patterns for fast detection (no LLM needed)
    LITERAL_PATTERNS = {
      deep_nesting: {
        pattern: /^(\s{8,})(if|unless|case|while|until|for|begin)/,
        principle: "KISS",
        message: "Deep nesting detected (4+ levels)",
        severity: :warning,
        autofix: false,
      },
      long_line: {
        pattern: /^.{120,}$/,
        principle: "KISS",
        message: "Line exceeds 120 characters",
        severity: :info,
        autofix: false,
      },
      complex_conditional: {
        pattern: /if\s+.*&&.*&&|if\s+.*\|\|.*\|\|/,
        principle: "KISS",
        message: "Complex conditional with multiple operators",
        severity: :warning,
        autofix: false,
      },
      magic_number: {
        pattern: /[^0-9a-z_]([2-9]\d{2,}|[1-9]\d{3,})[^0-9a-z_]/i,
        principle: "DRY",
        message: "Magic number detected (should be named constant)",
        severity: :info,
        autofix: true,
      },
      commented_code: {
        pattern: /^\s*#\s*(def |class |module |if |unless |case |while )/,
        principle: "YAGNI",
        message: "Commented out code detected",
        severity: :warning,
        autofix: true,
      },
      method_chain: {
        pattern: /\w+\.\w+\.\w+\.\w+/,
        principle: "Law of Demeter",
        message: "Long method chain (train wreck)",
        severity: :warning,
        autofix: false,
      },
      bare_rescue: {
        pattern: /rescue\s*$/,
        principle: "Fail Fast",
        message: "Bare rescue swallows errors silently",
        severity: :warning,
        autofix: true,
      },
      global_mutation: {
        pattern: %r{\$\w+\s*[+\-*/]?=},
        principle: "No Side Effects",
        message: "Global variable mutation",
        severity: :error,
        autofix: false,
      },
      class_variable_mutation: {
        pattern: %r{@@\w+\s*[+\-*/]?=},
        principle: "No Side Effects",
        message: "Class variable mutation",
        severity: :warning,
        autofix: false,
      },
      short_variable: {
        pattern: /\b([a-z])\s*=/,
        principle: "Meaningful Names",
        message: "Single letter variable name",
        severity: :info,
        autofix: true,
      },
      many_parameters: {
        pattern: /def\s+\w+\s*\(([^)]*,){4,}[^)]*\)/,
        principle: "Few Arguments",
        message: "Method has too many parameters (>4)",
        severity: :warning,
        autofix: false,
      },
      string_slice_magic: {
        pattern: /\[0\.\.\d{3,}\]/,
        principle: "DRY",
        message: "Magic number in string slice (use constant)",
        severity: :info,
        autofix: true,
      },
    }.freeze

    # Conceptual checks for LLM semantic analysis
    CONCEPTUAL_CHECKS = {
      kiss: {
        prompt: "Is this code unnecessarily complex? Could it be simpler?",
        examples: ["Metaprogramming when simple method works", "Over-abstracted hierarchies"],
      },
      dry: {
        prompt: "Is there duplicated logic that should be extracted?",
        examples: ["Similar error handling repeated", "Same validation in multiple places"],
      },
      yagni: {
        prompt: "Is there code built for hypothetical future requirements?",
        examples: ['Unused parameters "for future use"', "Abstract factories with single impl"],
      },
      single_responsibility: {
        prompt: "Does this class/module have more than one reason to change?",
        examples: ["Class handling business logic and persistence", "Method doing calculation and formatting"],
      },
      law_of_demeter: {
        prompt: "Does the code reach through objects to access internals?",
        examples: ["user.account.subscription.plan.price", "Deep nested hash access"],
      },
      fail_fast: {
        prompt: "Does the code validate inputs early or wait until problems propagate?",
        examples: ["Processing continues after invalid state", "Nil checks at end instead of beginning"],
      },
    }.freeze

    class << self
      def analyze(code, path: nil, llm: nil, conceptual: true)
        results = {
          literal: [],
          conceptual: [],
          summary: { errors: 0, warnings: 0, info: 0, total: 0 },
        }

        results[:literal] = detect_literal(code, path)
        results[:literal].each do |violation|
          key = violation[:severity]
          results[:summary][key] = (results[:summary][key] || 0) + 1
          results[:summary][:total] += 1
        end

        if conceptual && llm
          results[:conceptual] = detect_conceptual(code, path, llm)
          results[:conceptual].each do |_violation|
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

            enrichment = PrinciplesDb.enrich(config[:principle])
            violations << {
              type: :literal,
              name: name,
              principle: config[:principle],
              message: config[:message],
              severity: config[:severity],
              autofix: config.fetch(:autofix, false),
              line: idx + 1,
              match: line.strip[0..50],
              smell: enrichment&.dig(:smell),
              fix: enrichment&.dig(:fix),
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
        checks_to_run = CONCEPTUAL_CHECKS.keys.first(3)

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

          llm_result = llm.ask(prompt, tier: :cheap)
          next unless llm_result.ok?

          response = llm_result.value.to_s.downcase
          next if response.include?("no violations") || response.include?("code is clean")

          violations << {
            type: :conceptual,
            principle: principle.to_s.tr("_", " ").upcase,
            analysis: llm_result.value[0..MAX_ANALYSIS_PREVIEW],
            severity: :warning,
          }
        end

        violations
      end

      def quick_scan(path, llm: nil)
        return { error: "File not found" } unless File.exist?(path)

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
                   when :error then "-"
                   when :warning then "!"
                   else "."
                   end
            output << "  #{icon} #{v[:principle]}  #{v[:message]}"
            output << "    Line #{v[:line]}: #{v[:match]}" if v[:line]
          end
        end

        if results[:conceptual].any?
          output << ""
          output << "Conceptual (#{results[:conceptual].size})"
          results[:conceptual].each do |v|
            output << "  . #{v[:principle]}"
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
        code = lines.join

        methods_info = Analyzers::MethodLengthAnalyzer.scan(code)
        methods_info.each do |method|
          next unless method[:length] > 20

          violations << {
            type: :literal,
            name: :long_method,
            principle: "Small Functions",
            message: "Method '#{method[:name]}' is #{method[:length]} lines (>20)",
            severity: :warning,
            line: method[:start_line],
          }
        end

        violations
      end

      def check_require_count(code)
        requires = code.scan(/^require/).size + code.scan(/^require_relative/).size
        return [] if requires <= 10

        [{
          type: :literal,
          name: :many_requires,
          principle: "Single Responsibility",
          message: "File has #{requires} requires (high coupling)",
          severity: :warning,
          line: 1,
        }]
      end

      def check_repeated_strings(code)
        violations = []

        duplicates = Analyzers::RepeatedStringDetector.find(code, min_length: 8, min_count: 3)
        duplicates.each do |dup|
          str_preview = dup[:string].length > 30 ? "#{dup[:string][0...30]}..." : dup[:string]
          violations << {
            type: :literal,
            name: :repeated_string,
            principle: "DRY",
            message: "String #{str_preview} repeated #{dup[:count]} times",
            severity: :warning,
          }
        end

        violations
      end
    end
  end
end
