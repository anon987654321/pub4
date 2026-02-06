# frozen_string_literal: true

module MASTER
  module ZshPure
    # Validate that shell code uses Zsh-compatible syntax
    # Returns Result.ok(text) or Result.err(reason)
    def self.validate(text)
      # Extract shell code blocks
      code_blocks = extract_shell_blocks(text)
      return Result.ok(text) if code_blocks.empty?

      # Check each block for bash-isms
      code_blocks.each_with_index do |block, idx|
        error = check_bashisms(block)
        return Result.err("Shell block #{idx + 1}: #{error}") if error
      end

      Result.ok(text)
    end

    def self.extract_shell_blocks(text)
      blocks = []
      text.scan(/```(?:sh|bash|shell|zsh)\n(.*?)```/m) { |match| blocks << match[0] }
      blocks
    end

    def self.check_bashisms(code)
      # Check for 'function' keyword with parentheses (bash-ism)
      if code.match?(/^\s*function\s+\w+\s*\(\)/)
        return "Use 'function name' or 'name()' but not both"
      end

      # Check for 'source' command (should use '.' in POSIX/Zsh)
      if code.match?(/^\s*source\s+/)
        return "Use '. file' instead of 'source file' for portability"
      end

      # Check for bash array syntax that's incompatible
      if code.match?(/\[\s*\d+\s*\]=/)
        return "Array assignment syntax may not be portable"
      end

      # Check for bash-specific test constructs
      if code.match?(/\[\[.*=~.*\]\]/)
        return "Regex matching with =~ inside [[ ]] is bash-specific"
      end

      nil # No errors found
    end
  end
end
