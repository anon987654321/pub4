# frozen_string_literal: true

module MASTER
  # DangerousPatterns — single source of truth for blocked commands
  # Loaded from data/dangerous_patterns.yml
  module DangerousPatterns
    PATTERNS_FILE = File.join(__dir__, "..", "data", "dangerous_patterns.yml")

    class << self
      def patterns
        @patterns ||= load_patterns
      end

      def dangerous?(text)
        patterns.any? { |p| text.match?(p[:regex]) }
      end

      def check(text)
        patterns.each do |p|
          if text.match?(p[:regex])
            return { dangerous: true, pattern: p[:name], description: p[:description] }
          end
        end
        { dangerous: false }
      end

      def reload!
        @patterns = nil
        patterns
      end

      private

      def load_patterns
        return [] unless File.exist?(PATTERNS_FILE)
        config = YAML.safe_load_file(PATTERNS_FILE, symbolize_names: true)
        (config[:patterns] || []).map do |p|
          flags = p[:case_insensitive] ? Regexp::IGNORECASE : 0
          { name: p[:name], regex: Regexp.new(p[:regex], flags), description: p[:description] }
        end
      end
    end
  end
end
