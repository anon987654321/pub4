# frozen_string_literal: true

module MASTER
  # Safety - Centralized dangerous pattern and path checking
  # Extracted from Executor to be reusable across modules
  module Safety
    DANGEROUS_PATTERNS = [
      /rm\s+-r[f]?\s+\//,
      />\s*\/dev\/[sh]da/,
      /DROP\s+TABLE/i,
      /FORMAT\s+[A-Z]:/i,
      /mkfs\./,
      /dd\s+if=/,
    ].freeze

    PROTECTED_WRITE_PATHS = %w[
      data/constitution.yml
      /etc/
      /usr/
      /sys/
      /proc/
      /dev/
      /boot/
    ].freeze

    class << self
      def dangerous?(input)
        text = input.to_s
        DANGEROUS_PATTERNS.any? { |p| text.match?(p) }
      end

      def protected_path?(path)
        PROTECTED_WRITE_PATHS.any? { |p| path.to_s.start_with?(p) }
      end

      def check(input)
        if dangerous?(input)
          Result.err("Blocked: dangerous pattern detected")
        else
          Result.ok(input)
        end
      end
    end
  end
end
