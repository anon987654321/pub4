# frozen_string_literal: true

module MASTER
  module Safety
    # Dangerous command patterns (from PR #64)
    DANGEROUS_COMMANDS = [
      /rm\s+-rf\s+[~\/]/,           # rm -rf ~ or /
      /:\(\)\s*\{/,                  # Fork bomb
      /dd\s+.*of=\/dev/,             # Destructive dd
      /\.ssh\/authorized_keys/,      # SSH key manipulation
      /mkfs\./,                      # Format filesystem
      />\s*\/dev\/sd/,               # Write to raw device
      /chmod\s+-R\s+777/,            # Unsafe permissions
      /curl.*\|\s*(ba)?sh/,          # Pipe curl to shell
    ].freeze

    DANGEROUS_RUBY = [
      /\bsystem\s*\(/,               # system() calls
      /\bexec\s*\(/,                 # exec() calls
      /`[^`]+`/,                     # Backticks
      /File\.(delete|unlink)/,       # File deletion
      /FileUtils\.(rm|remove)/,      # FileUtils deletion
      /\beval\s*\(/,                 # Dynamic eval
      /\binstance_eval/,             # Instance eval
      /\bclass_eval/,                # Class eval
      /Socket\.(new|open)/,          # Raw sockets
    ].freeze

    class << self
      def command_safe?(command)
        DANGEROUS_COMMANDS.none? { |pattern| command.match?(pattern) }
      end

      def ruby_safe?(code)
        DANGEROUS_RUBY.none? { |pattern| code.match?(pattern) }
      end

      def validate_command(command)
        return Result.ok(command) if command_safe?(command)

        matched = DANGEROUS_COMMANDS.find { |p| command.match?(p) }
        Result.err("Blocked dangerous pattern: #{matched.source}")
      end

      def validate_ruby(code)
        return Result.ok(code) if ruby_safe?(code)

        matched = DANGEROUS_RUBY.find { |p| code.match?(p) }
        Result.err("Blocked dangerous pattern: #{matched.source}")
      end
    end
  end
end
