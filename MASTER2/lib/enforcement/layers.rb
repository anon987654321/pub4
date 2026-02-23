# frozen_string_literal: true

require_relative "../code_review/analyzers"

module MASTER
  module Enforcement
    module_function

    def self_check!
      MASTER::Review::Enforcer.self_check!
    end

    def check(code, **)
      MASTER::Review::Enforcer.check(code, **)
    end

    LAYERS = %i[literal lexical structural semantic behavioral cognitive].freeze

    # Six axiom enforcement layers
    module Layers
      # Layer 1: Literal - exact string/pattern matching
      def check_literal(code, axioms, filename)
        violations = []

        # NOTE: TODO/FIXME/XXX/HACK and bare rescue checks are in check_lines (scope 1)
        # to avoid double-counting violations

        # Hardcoded secrets
        if code.match?(/['"][A-Za-z0-9]{32,}['"]/)
          violations << { layer: :literal, axiom: "SINGLE_SOURCE", message: "Possible hardcoded secret",
                          file: filename }
        end

        # Check core axioms with detect patterns from axioms.yml
        axioms.each do |axiom|
          axiom_id = axiom["id"] || axiom[:id]
          pattern_str = axiom["detect"] || axiom[:detect]
          suggest = axiom["suggest"] || axiom[:suggest]
          negative_pattern_str = axiom["negative_detect"] || axiom[:negative_detect]

          next if pattern_str.nil? # Skip axioms without detect patterns

          begin
            pattern = Regexp.new(pattern_str, Regexp::MULTILINE)

            # Check if code matches the violation pattern
            if code.match?(pattern)
              # If there's a negative pattern, check that too
              if negative_pattern_str
                negative_pattern = Regexp.new(negative_pattern_str, Regexp::MULTILINE)
                # Only flag if negative pattern is NOT found (i.e., timeout is missing)
                next if code.match?(negative_pattern)
              end

              violations << {
                layer: :literal,
                axiom: axiom_id,
                message: suggest || "Axiom #{axiom_id} violation detected",
                protection: axiom["protection"] || axiom[:protection],
                file: filename,
              }
            end
          rescue RegexpError
            # Skip invalid patterns
            next
          end
        end

        violations
      end

      # Layer 2: Lexical - token/syntax analysis
      def check_lexical(code, _axioms, filename)
        nesting_limit = thresholds["nesting_depth"] || 4
        method_limit = thresholds["method_length"] || 50

        # DRY: duplicate method definitions
        methods = code.scan(/def\s+(\w+)/).flatten
        duplicates = methods.select { |method_name| methods.count(method_name) > 1 }.uniq
        violations = duplicates.map do |method|
          { layer: :lexical, axiom: "DRY", message: "Duplicate method: #{method}", file: filename }
        end

        # STRUCTURAL_FLATTEN: excessive nesting
        max_nesting = Analyzers::NestingAnalyzer.depth(code)
        if max_nesting > nesting_limit
          violations << { layer: :lexical, axiom: "STRUCTURAL_FLATTEN",
                          message: "Excessive nesting (#{max_nesting} levels)", file: filename }
        end

        # KISS: overly long methods
        methods_info = Analyzers::MethodLengthAnalyzer.scan(code)
        methods_info.each do |method|
          if method[:length] > method_limit
            violations << { layer: :lexical, axiom: "KISS",
                            message: "Method too long: #{method[:name]} (#{method[:length]} lines)", file: filename }
          end
        end

        violations
      end

      # Layer 3: Conceptual - structural patterns
      def check_conceptual(code, _axioms, filename)
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
            violations << { layer: :conceptual, axiom: "STRUCTURAL_HOIST", message: "I/O operation inside loop",
                            file: filename }
          end
        end

        # STRUCTURAL_COALESCE: sequential same-type operations
        if code.scan(/\.save\b/).size > 3
          violations << { layer: :conceptual, axiom: "STRUCTURAL_COALESCE",
                          message: "Multiple sequential saves - consider bulk operation", file: filename }
        end

        violations
      end

      # Layer 4: Semantic - meaning/intent analysis
      def check_semantic(code, _axioms, filename)
        violations = []
        generic_verbs = smells["generic_verbs"] || {}
        vague_nouns = smells["vague_nouns"] || {}

        # Check for generic verbs in method names
        generic_verbs.each_key do |verb|
          next unless code.match?(/def\s+#{verb}_\w+/)

          better = generic_verbs[verb]&.first
          msg = better ? "Generic verb '#{verb}' - try '#{better}'" : "Generic verb '#{verb}'"
          violations << { layer: :semantic, axiom: "OMIT_WORDS", message: msg, file: filename }
        end

        # Check for vague nouns in variable/class names
        vague_nouns.each_key do |noun|
          next unless code.match?(/\b#{noun}\s*=/) || code.match?(/class\s+\w*#{noun.capitalize}/)

          better = vague_nouns[noun]&.first
          msg = better ? "Vague noun '#{noun}' - try '#{better}'" : "Vague noun '#{noun}'"
          violations << { layer: :semantic, axiom: "OMIT_WORDS", message: msg, file: filename }
        end

        # ACTIVE_VOICE: passive method names
        passive_patterns = [/is_(\w+)_by/, /was_(\w+)/, /been_(\w+)/]
        passive_patterns.each do |pattern|
          next unless code.match?(pattern)

          violations << { layer: :semantic, axiom: "ACTIVE_VOICE", message: "Passive voice in method name",
                          file: filename }
          break
        end

        violations
      end

      # Layer 5: Cognitive - human understanding
      def check_cognitive(code, _axioms, filename)
        violations = []

        # HIERARCHY: inconsistent structure
        class_count = code.scan(/^\s*class\s+\w+/).size
        module_count = code.scan(/^\s*module\s+\w+/).size
        if class_count > 3 || module_count > 3
          violations << { layer: :cognitive, axiom: "HIERARCHY", message: "Too many classes/modules in one file",
                          file: filename }
        end

        # RHYTHM: inconsistent spacing
        blank_line_gaps = code.scan(/\n(\n+)/).map { |match| match.first.length }
        if blank_line_gaps.uniq.size > 2
          violations << { layer: :cognitive, axiom: "RHYTHM", message: "Inconsistent blank line spacing",
                          file: filename }
        end

        # POLA: surprising patterns
        if code.match?(/def\s+\[\]=?/) && !filename.include?("collection")
          violations << { layer: :cognitive, axiom: "POLA", message: "Operator overloading may surprise users",
                          file: filename }
        end

        # PROGRESSIVE_DISCLOSURE: all complexity upfront
        if code.lines.first(20).join.scan(/def\s+/).size > 5
          violations << { layer: :cognitive, axiom: "PROGRESSIVE_DISCLOSURE",
                          message: "Too many methods defined before any implementation", file: filename }
        end

        violations
      end

      # Layer 6: Language axiom - language-specific beauty rules
      def check_language_axiom(code, _axioms, filename)
        if defined?(LanguageAxioms)
          LanguageAxioms.check(code, filename: filename)
        else
          []
        end
      end
      # Additional checks from Validator (merged for ONE_SOURCE compliance)

      # KISS: Only flag unnecessary complexity in internal logic
      # Never remove: UI/UX features, user-facing functionality, accessibility, error messages
      KISS_PROTECTED_PATTERNS = [
        /ui/i, /ux/i, /user/i, /display/i, /render/i, /print/i, /puts/i,
        /progress/i, /spinner/i, /prompt/i, /help/i, /error/i, /warning/i,
        /autocomplete/i, /accessibility/i, /a11y/i, /feedback/i, /message/i
      ].freeze

      # Check SRP (Single Responsibility Principle)
      def check_srp(code, filename: "code")
        violations = []

        # Check for too many class definitions
        classes = code.scan(/^\s*class\s+\w+/).size
        if classes > 1
          violations << { layer: :lexical, axiom: "ONE_JOB", message: "Multiple classes in single file",
                          file: filename }
        end

        # Check for too many public methods
        methods = code.scan(/^\s*def\s+(?!private|protected)/).size
        if methods > 10
          violations << { layer: :lexical, axiom: "ONE_JOB", message: "Too many methods (>10)", file: filename }
        end

        violations
      end

      # Check KISS (Keep It Simple)
      def check_kiss_complexity(code, filename: "code")
        violations = []

        # Skip KISS checks for UI/UX related code
        return violations if KISS_PROTECTED_PATTERNS.any? { |pat| code.match?(pat) }

        # Check for deeply nested code (internal logic complexity)
        max_nesting = Analyzers::NestingAnalyzer.depth(code)
        if max_nesting > 6
          violations << { layer: :lexical, axiom: "KISS", message: "Deeply nested internal logic (>6 levels)",
                          file: filename }
        end

        violations
      end

      # Check DRY (Don't Repeat Yourself)
      def check_dry_violations(code, filename: "code")
        violations = []

        # Look for duplicate string literals (both single and double quotes)
        duplicates = Analyzers::RepeatedStringDetector.find(code, min_length: 8, min_count: 3)

        duplicates.each do |dup|
          str_preview = dup[:string].length > 30 ? "#{dup[:string][0...30]}..." : dup[:string]
          violations << { layer: :lexical, axiom: "ONE_SOURCE",
                          message: "Repeated string: '#{str_preview}' (#{dup[:count]} times)", file: filename }
        end

        violations
      end

      # Check file size
      def check_file_size_violation(code, filename: "code")
        violations = []
        lines = code.lines.size
        max_lines = QualityStandards.max_file_lines

        if lines > max_lines
          violations << { layer: :cognitive, axiom: "JUST_ENOUGH",
                          message: "File too large: #{lines} lines (limit: #{max_lines})", file: filename }
        end

        violations
      end

      # Check metaprogramming policy (constitution.yml metaprogramming_policy.banned_patterns)
      def check_metaprogramming(code, filename: "code")
        @meta_banned ||= begin
          f = Paths.data_file("constitution.yml")
          YAML.safe_load_file(f)&.dig("metaprogramming_policy", "banned_patterns") || []
        rescue StandardError
          []
        end
        violations = []
        @meta_banned.each do |pattern|
          re = /\b#{Regexp.escape(pattern)}\b/
          code.each_line.with_index(1) do |line, lineno|
            next if line.strip.start_with?("#")

            if re.match?(line)
              violations << {
                layer: :semantic, axiom: "EXPLICIT",
                message: "Banned metaprogramming: #{pattern} -- prefer explicit method definition",
                file: filename, line: lineno,
              }
            end
          end
        end
        violations
      end

      # Importance-flow (INVERTED_PYRAMID) smell detectors
      # Checks that files are laid out top-to-bottom by descending importance.
      IMPORTANCE_PATTERNS = [
        { smell: :rescue_wraps_def,   axiom: "INVERTED_PYRAMID",
          re: /\bdef\s+\w+[^#\n]*\n(?:.*\n)*?\s+rescue\b/m,
          message: "rescue wraps entire method body -- narrow to the raising expression; move guard first" },
        { smell: :private_before_public, axiom: "INVERTED_PYRAMID",
          re: /\bprivate\b[\s\S]*?\bdef\s+\w/m,
          message: "private keyword appears before a method definition -- move private block to bottom of class" },
        { smell: :required_after_optional, axiom: "INVERTED_PYRAMID",
          re: /def\s+\w+\([^)]*\w\s*=\s*[^,)]+,\s*\w+[^=,)]*\)/,
          message: "optional param before required -- reorder: required -> optional -> keyword -> block" },
        { smell: :helpers_before_core, axiom: "INVERTED_PYRAMID",
          re: /\bprivate\b.*\ndef\s+\w+.*\bpublic\b/m,
          message: "public method defined after private block -- hoist public interface to top" },
      ].freeze

      def check_importance_flow(code, filename: "code")
        return [] unless filename.end_with?(".rb")

        violations = []
        IMPORTANCE_PATTERNS.each do |pat|
          next unless code.match?(pat[:re])

          violations << {
            layer: :structural,
            axiom: pat[:axiom],
            message: pat[:message],
            severity: :warning,
            file: filename,
          }
        end
        violations
      end

      # Structural optimization smell detector -- uses structural_optimization section of smells.yml
      # Catches atomic/local patterns: buried constants, dead assigns, generic get_ names, etc.
      STRUCTURAL_PATTERNS = [
        { smell: :buried_constant,    axiom: "STRUCTURAL_INTEGRITY",
          re: /^\s+(SCREAMING_SNAKE|[A-Z][A-Z_]{2,})\s*=\s*[^=]/,
          message: "Constant defined inside method body -- hoist to module level" },
        { smell: :naming_drift,       axiom: "STRUCTURAL_INTEGRITY",
          re: /\bdef\s+get_\w+/,
          message: "get_ prefix is a generic verb smell -- rename to noun (fetch/load/find)" },
        { smell: :abstraction_gap,    axiom: "STRUCTURAL_INTEGRITY",
          re: /YAML\.safe_load_file\(.+\)\s*rescue/,
          message: "Inline YAML load+rescue repeated -- extract to Paths.load_data_file helper" },
        { smell: :abstraction_gap,    axiom: "STRUCTURAL_INTEGRITY",
          re: /File\.join\(.*['"]data['"].*\.yml['"]\)/,
          message: "Hardcoded data/ path -- use Paths.data_file(name) abstraction" },
        { smell: :layering_violation, axiom: "META_COHERENCE",
          re: /^\s+puts\s|^\s+print\s|UI\.(warn|info|success)\b/,
          message: "UI output inside business logic -- return result; let caller display" },
      ].freeze

      def check_structural_smells(code, filename: "code")
        violations = []
        STRUCTURAL_PATTERNS.each do |pat|
          next unless code.match?(pat[:re])

          violations << {
            layer: :structural,
            axiom: pat[:axiom],
            message: pat[:message],
            severity: :warning,
            file: filename,
          }
        end
        violations
      end

      # Strunk & White prose quality detectors -- STRUNK_WHITE axiom.
      # Applied to identifiers, comments, strings, and error messages.
      PROSE_PATTERNS = [
        { smell: :filler_identifier,    axiom: "STRUNK_WHITE",
          re: /\b(?:local\s+)?(?:var\s+)?(data|info|thing|stuff|misc|temp|tmp)\b\s*=/,
          message: "Filler identifier -- replace with the specific domain noun (axiom_list, cost_ratio, violation_count)" },
        { smell: :passive_prefix_method, axiom: "STRUNK_WHITE",
          re: /\bdef\s+(?:do|perform|process|handle|execute|manage)_\w+/,
          message: "Passive prefix method -- rename to active verb (enforce, scan, reflow, build)" },
        { smell: :filler_phrase,        axiom: "STRUNK_WHITE",
          re: /['"].*(?:in order to|the fact that|it is important to|it should be noted|please note|as you can see).*['"]/i,
          message: "Filler phrase in string -- cut the preamble; state the substance directly" },
        { smell: :qualifier_word,       axiom: "STRUNK_WHITE",
          re: /['"].*\b(?:basically|essentially|actually|simply|really|quite|very)\b.*['"]/i,
          message: "Qualifier word in string -- cut it; rewrite with precision instead" },
        { smell: :passive_error_message, axiom: "STRUNK_WHITE",
          re: /(?:raise|warn|error|Error\.new).*(?:was rejected|were found|was created|is handled|be processed)/i,
          message: "Passive error message -- rewrite in active voice: 'Enforcer rejected X' not 'X was rejected'" },
        { smell: :zombie_noun,          axiom: "STRUNK_WHITE",
          re: /#.*\b(?:the refactoring of|the enforcement of|a validation of|the processing of)\b/i,
          message: "Zombie noun in comment -- convert to verb: 'refactor', 'enforce', 'validate'" },
        { smell: :vague_class_name,     axiom: "STRUNK_WHITE",
          re: /\bclass\s+\w*(?:Manager|Handler|Processor|Helper|Util)\b/,
          message: "Vague class name suffix -- name by domain role: ViolationReporter, AxiomLoader, CostTracker" },
      ].freeze

      def check_prose_style(code, filename: "code")
        violations = []
        PROSE_PATTERNS.each do |pat|
          next unless code.match?(pat[:re])

          violations << {
            layer: :prose,
            axiom: pat[:axiom],
            message: pat[:message],
            severity: :warning,
            file: filename,
          }
        end
        violations
      end

      def check_learned_smells(code, filename: "code")
        smells = defined?(DB) ? DB.learned_smells : []
        return [] if smells.empty?

        violations = []
        smells.each do |smell|
          next if smell[:pattern].to_s.empty?

          begin
            re = Regexp.new(smell[:pattern], Regexp::MULTILINE)
          rescue RegexpError
            next
          end

          next unless code.match?(re)

          DB.increment_smell_hit(smell[:pattern]) rescue nil
          violations << {
            layer: :learned_smell,
            axiom: "QUALITY",
            message: smell[:description] || "Learned smell: #{smell[:pattern]}",
            severity: (smell[:severity] || :info).to_sym,
            file: filename,
          }
        end
        violations
      end
    end
  end
end
