# frozen_string_literal: true

module MASTER
  module Enforcement
    # Six axiom enforcement layers
    module Layers
      # Layer 1: Literal - exact string/pattern matching
      def check_literal(code, axioms, filename)
        violations = []

        # Note: TODO/FIXME/XXX/HACK and bare rescue checks are in check_lines (scope 1)
        # to avoid double-counting violations

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
