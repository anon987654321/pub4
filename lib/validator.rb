# frozen_string_literal: true

module MASTER
  # Validator - Axiom enforcement engine
  class Validator
    def initialize
      @axioms = DB.axioms rescue []
    end

    def validate(code:, context: {})
      violations = []

      @axioms.each do |axiom|
        next unless applies?(axiom, context)
        
        violation = check_axiom(axiom, code)
        violations << violation if violation
      end

      if violations.empty?
        Result.ok({ valid: true, axioms_checked: @axioms.size })
      else
        Result.err({ valid: false, violations: violations })
      end
    end

    def validate_response(text)
      issues = []

      # Check for code blocks
      if text.include?('```')
        code_blocks = text.scan(/```\w*\n(.*?)```/m).flatten
        code_blocks.each do |code|
          result = validate(code: code)
          issues.concat(result.error[:violations]) if result.err?
        end
      end

      issues
    end

    private

    def applies?(axiom, context)
      return true if axiom['applies_to'].nil?
      
      applies_to = axiom['applies_to']
      return true if applies_to == 'all'
      
      context[:type]&.to_s == applies_to
    end

    def check_axiom(axiom, code)
      name = axiom['name'] || axiom[:name]
      
      case name
      when 'SRP', 'Single Responsibility'
        check_srp(code)
      when 'KISS'
        check_kiss(code)
      when 'DRY'
        check_dry(code)
      when 'small_files'
        check_file_size(code)
      else
        nil
      end
    end

    def check_srp(code)
      # Check for too many class definitions
      classes = code.scan(/^\s*class\s+\w+/).size
      return { axiom: 'SRP', message: 'Multiple classes in single file' } if classes > 1

      # Check for too many public methods
      methods = code.scan(/^\s*def\s+(?!private|protected)/).size
      return { axiom: 'SRP', message: 'Too many methods (>10)' } if methods > 10

      nil
    end

    # KISS: Only flag unnecessary complexity in internal logic
    # Never remove: UI/UX features, user-facing functionality, accessibility, error messages
    KISS_PROTECTED_PATTERNS = [
      /ui/i, /ux/i, /user/i, /display/i, /render/i, /print/i, /puts/i,
      /progress/i, /spinner/i, /prompt/i, /help/i, /error/i, /warning/i,
      /autocomplete/i, /accessibility/i, /a11y/i, /feedback/i, /message/i
    ].freeze

    def check_kiss(code)
      # Skip KISS checks for UI/UX related code
      return nil if KISS_PROTECTED_PATTERNS.any? { |pat| code.match?(pat) }

      lines = code.lines

      # Check for deeply nested code (internal logic complexity)
      max_indent = lines.map { |l| l.match(/^(\s*)/)[1].length }.max || 0
      return { axiom: 'KISS', message: 'Deeply nested internal logic (>6 levels)' } if max_indent > 24

      nil
    end

    def check_dry(code)
      # Look for duplicate string literals
      strings = code.scan(/"([^"]+)"/).flatten
      duplicates = strings.group_by(&:itself).select { |_, v| v.size > 2 }
      
      if duplicates.any?
        { axiom: 'DRY', message: "Repeated strings: #{duplicates.keys.first(3).join(', ')}" }
      else
        nil
      end
    end

    def check_file_size(code)
      lines = code.lines.size
      return { axiom: 'small_files', message: "File too large: #{lines} lines" } if lines > 300

      nil
    end
  end
end
