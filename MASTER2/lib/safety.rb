# frozen_string_literal: true

module MASTER
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

    def self.dangerous?(text)
      DANGEROUS_PATTERNS.any? { |p| text.match?(p) }
    end

    def self.protected_path?(path)
      return true if defined?(Constitution) && Constitution.respond_to?(:protected_file?) && Constitution.protected_file?(path)
      PROTECTED_WRITE_PATHS.any? { |p| path.include?(p) }
    end
  end
end
