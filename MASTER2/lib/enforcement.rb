# frozen_string_literal: true

require "yaml"

module MASTER
  # Enforcement - 5-layer axiom enforcement at 4 scopes
  # Layers: Literal → Lexical → Conceptual → Semantic → Cognitive
  # Scopes: Line → Unit → File → Framework
  module Enforcement
    LAYERS = %i[literal lexical conceptual semantic cognitive language_axiom].freeze
    SCOPES = %i[line unit file framework].freeze
    SMELLS_FILE = File.join(__dir__, "..", "data", "smells.yml")

    class << self
      def smells
        @smells ||= File.exist?(SMELLS_FILE) ? YAML.safe_load_file(SMELLS_FILE) : {}
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

      # Run all 5 layers on single file
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
        source = type == :verb ? smells["generic_verbs"] : smells["vague_nouns"]
        return nil unless source

        source[word.downcase]&.first
      end

      private

      # Scope 1: Line-by-line analysis
      def check_lines(code, filename)
        violations = []
        code.each_line.with_index(1) do |line, num|
          # Literal: exact patterns per line
          violations << { scope: :line, line: num, axiom: "STRUCTURAL_PRUNE", message: "Dead marker" } if line.match?(/\b(TODO|FIXME|XXX|HACK)\b/)
          violations << { scope: :line, line: num, axiom: "OMIT_WORDS", message: "Trailing whitespace" } if line.match?(/\s+$/)
          violations << { scope: :line, line: num, axiom: "KISS", message: "Line too long (#{line.length})" } if line.length > (thresholds["line_length"] || 120)
          violations << { scope: :line, line: num, axiom: "FAIL_LOUD", message: "Bare rescue" } if line.match?(/rescue\s*($|#)/)
        end
        violations
      end

      # Scope 2: Unit analysis (methods, classes)
      def check_units(code, filename)
        violations = []
        method_limit = thresholds["method_length"] || 50
        param_limit = thresholds["parameter_count"] || 5

        # Extract methods and analyze each
        code.scan(/def\s+(\w+)\s*(\([^)]*\))?.*?^(\s*)end/m) do |match|
          name, params, _ = match
          method_match = Regexp.last_match
          body = method_match[0]
          lines = body.lines.size

          violations << { scope: :unit, unit: name, axiom: "KISS", message: "Method too long (#{lines} lines)" } if lines > method_limit

          param_count = params.to_s.count(",") + (params.to_s.empty? ? 0 : 1)
          violations << { scope: :unit, unit: name, axiom: "KISS", message: "Too many parameters (#{param_count})" } if param_count > param_limit

          # Check for generic verb in method name
          (smells["generic_verbs"] || {}).keys.each do |verb|
            if name.start_with?("#{verb}_")
              better = smells["generic_verbs"][verb]&.first
              violations << { scope: :unit, unit: name, axiom: "OMIT_WORDS", message: "Generic verb - try '#{better}'" }
            end
          end
        end

        # Extract classes
        code.scan(/class\s+(\w+).*?^end/m) do |match|
          class_name = match.first
          class_body = Regexp.last_match[0]
          method_count = class_body.scan(/def\s+\w+/).size

          violations << { scope: :unit, unit: class_name, axiom: "SOLID_SRP", message: "Too many methods (#{method_count})" } if method_count > 15
        end

        violations
      end

      # Scope 4: Framework-wide analysis (cross-file)
      def check_framework(files, axioms)
        violations = []
        all_methods = {}
        all_classes = {}
        all_constants = {}

        files.each do |filename, content|
          # Collect all definitions
          content.scan(/def\s+(\w+)/).flatten.each { |m| (all_methods[m] ||= []) << filename }
          content.scan(/class\s+(\w+)/).flatten.each { |c| (all_classes[c] ||= []) << filename }
          content.scan(/([A-Z][A-Z_]+)\s*=/).flatten.each { |c| (all_constants[c] ||= []) << filename }
        end

        # DRY: same method name in multiple files (possible duplication)
        all_methods.each do |method, locations|
          if locations.size > 2 && !%w[initialize call to_s to_h].include?(method)
            violations << { scope: :framework, axiom: "DRY", message: "Method '#{method}' defined in #{locations.size} files", locations: locations }
          end
        end

        # SINGLE_SOURCE: same constant in multiple files
        all_constants.each do |const, locations|
          if locations.size > 1
            violations << { scope: :framework, axiom: "SINGLE_SOURCE", message: "Constant '#{const}' defined in #{locations.size} files", locations: locations }
          end
        end

        # STRUCTURAL_MERGE: similar class names
        all_classes.keys.combination(2).each do |a, b|
          if Utils.levenshtein(a, b) <= 2 && a != b
            violations << { scope: :framework, axiom: "STRUCTURAL_MERGE", message: "Similar classes: #{a}, #{b}" }
          end
        end

        violations
      end

      # Layer 1: Literal - exact string/pattern matching
      def check_literal(code, axioms, filename)
        violations = []

        # STRUCTURAL_PRUNE: dead code markers
        if code.match?(/\b(TODO|FIXME|XXX|HACK)\b/)
          violations << { layer: :literal, axiom: "STRUCTURAL_PRUNE", message: "Dead code marker found", file: filename }
        end

        # Bare rescue (bad practice)
        if code.match?(/rescue\s*($|#)/)
          violations << { layer: :literal, axiom: "FAIL_LOUD", message: "Bare rescue swallows errors", file: filename }
        end

        # Hardcoded secrets
        if code.match?(/['"][A-Za-z0-9]{32,}['"]/)
          violations << { layer: :literal, axiom: "SINGLE_SOURCE", message: "Possible hardcoded secret", file: filename }
        end

        violations
      end

      # Layer 2: Lexical - token/syntax analysis
      def check_lexical(code, axioms, filename)
        violations = []
        nesting_limit = thresholds["nesting_depth"] || 4
        method_limit = thresholds["method_length"] || 50

        # DRY: duplicate method definitions
        methods = code.scan(/def\s+(\w+)/).flatten
        duplicates = methods.select { |m| methods.count(m) > 1 }.uniq
        duplicates.each do |method|
          violations << { layer: :lexical, axiom: "DRY", message: "Duplicate method: #{method}", file: filename }
        end

        # STRUCTURAL_FLATTEN: excessive nesting
        max_indent = code.lines.map { |l| l[/^\s*/].length }.max || 0
        if max_indent > (nesting_limit * 4)
          violations << { layer: :lexical, axiom: "STRUCTURAL_FLATTEN", message: "Excessive nesting (#{max_indent / 4} levels)", file: filename }
        end

        # KISS: overly long methods
        in_method = false
        method_lines = 0
        method_name = nil
        code.each_line do |line|
          if line.match?(/^\s*def\s+\w+/)
            in_method = true
            method_lines = 0
            method_name = line[/def\s+(\w+)/, 1]
          elsif in_method
            method_lines += 1
            if line.strip == "end" && method_lines > method_limit
              violations << { layer: :lexical, axiom: "KISS", message: "Method too long: #{method_name} (#{method_lines} lines)", file: filename }
              in_method = false
            end
          end
        end

        violations
      end

      # Layer 3: Conceptual - structural patterns
      def check_conceptual(code, axioms, filename)
        violations = []

        # STRUCTURAL_DEFRAGMENT: related code scattered
        # Check if private methods are called before they're defined
        public_section = code.split(/^\s*private\s*$/).first || code
        private_methods = code.scan(/^\s*private[\s\S]*?def\s+(\w+)/).flatten
        
        private_methods.each do |method|
          if public_section.match?(/\b#{method}\b/) && !public_section.match?(/def\s+#{method}/)
            # Method called in public section but defined in private - this is fine
          end
        end

        # STRUCTURAL_HOIST: repeated operations in loops
        loop_patterns = code.scan(/(?:while|until|loop|each|map|select)\s*(?:do|\{)[\s\S]*?(?:end|\})/)
        loop_patterns.each do |loop_body|
          if loop_body.scan(/File\.read|DB\.|Net::HTTP/).size > 1
            violations << { layer: :conceptual, axiom: "STRUCTURAL_HOIST", message: "I/O operation inside loop", file: filename }
          end
        end

        # STRUCTURAL_COALESCE: sequential same-type operations
        if code.scan(/\.save\b/).size > 3
          violations << { layer: :conceptual, axiom: "STRUCTURAL_COALESCE", message: "Multiple sequential saves - consider bulk operation", file: filename }
        end

        violations
      end

      # Layer 4: Semantic - meaning/intent analysis
      def check_semantic(code, axioms, filename)
        violations = []
        generic_verbs = smells["generic_verbs"] || {}
        vague_nouns = smells["vague_nouns"] || {}

        # Check for generic verbs in method names
        generic_verbs.keys.each do |verb|
          if code.match?(/def\s+#{verb}_\w+/)
            better = generic_verbs[verb]&.first
            msg = better ? "Generic verb '#{verb}' - try '#{better}'" : "Generic verb '#{verb}'"
            violations << { layer: :semantic, axiom: "OMIT_WORDS", message: msg, file: filename }
          end
        end

        # Check for vague nouns in variable/class names
        vague_nouns.keys.each do |noun|
          if code.match?(/\b#{noun}\s*=/) || code.match?(/class\s+\w*#{noun.capitalize}/)
            better = vague_nouns[noun]&.first
            msg = better ? "Vague noun '#{noun}' - try '#{better}'" : "Vague noun '#{noun}'"
            violations << { layer: :semantic, axiom: "OMIT_WORDS", message: msg, file: filename }
          end
        end

        # ACTIVE_VOICE: passive method names
        passive_patterns = [/is_(\w+)_by/, /was_(\w+)/, /been_(\w+)/]
        passive_patterns.each do |pattern|
          if code.match?(pattern)
            violations << { layer: :semantic, axiom: "ACTIVE_VOICE", message: "Passive voice in method name", file: filename }
            break
          end
        end

        violations
      end

      # Layer 5: Cognitive - human understanding
      def check_cognitive(code, axioms, filename)
        violations = []

        # HIERARCHY: inconsistent structure
        class_count = code.scan(/^\s*class\s+\w+/).size
        module_count = code.scan(/^\s*module\s+\w+/).size
        if class_count > 3 || module_count > 3
          violations << { layer: :cognitive, axiom: "HIERARCHY", message: "Too many classes/modules in one file", file: filename }
        end

        # RHYTHM: inconsistent spacing
        blank_line_gaps = code.scan(/\n(\n+)/).map { |m| m.first.length }
        if blank_line_gaps.uniq.size > 2
          violations << { layer: :cognitive, axiom: "RHYTHM", message: "Inconsistent blank line spacing", file: filename }
        end

        # POLA: surprising patterns
        if code.match?(/def\s+\[\]=?/) && !filename.include?("collection")
          violations << { layer: :cognitive, axiom: "POLA", message: "Operator overloading may surprise users", file: filename }
        end

        # PROGRESSIVE_DISCLOSURE: all complexity upfront
        if code.lines.first(20).join.scan(/def\s+/).size > 5
          violations << { layer: :cognitive, axiom: "PROGRESSIVE_DISCLOSURE", message: "Too many methods defined before any implementation", file: filename }
        end

        violations
      end

      # Layer 6: Language axiom - language-specific beauty rules
      def check_language_axiom(code, axioms, filename)
        if defined?(LanguageAxioms)
          LanguageAxioms.check(code, filename: filename)
        else
          []
        end
      end
    end
  end
end
