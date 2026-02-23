# frozen_string_literal: true

module MASTER
  module Stages
    # Stage 2: Strip filler words and verbose phrases
    class Compress
      COMPRESSION_FILE = File.join(__dir__, "..", "..", "data", "compression.yml")

      class << self
        # @return [Hash] Hash with :fillers and :phrases arrays
        def patterns
          @patterns ||= load_patterns
        end

        # @return [Hash] Compiled regex patterns
        def load_patterns
          return { fillers: [], phrases: [] } unless File.exist?(COMPRESSION_FILE)

          yaml_data = YAML.safe_load_file(COMPRESSION_FILE)
          {
            fillers: (yaml_data["fillers"] || []).map { |w| /\b#{Regexp.escape(w)}\b/i },
            phrases: (yaml_data["phrases"] || []).map { |p| /#{Regexp.escape(p)}/i },
          }
        end
      end

      def call(input)
        text = input[:text] || ""
        original_length = text.length

        # Strip filler words
        self.class.patterns[:fillers].each do |pattern|
          text = text.gsub(pattern, "")
        end

        # Simplify verbose phrases
        self.class.patterns[:phrases].each do |pattern|
          text = text.gsub(pattern, "")
        end

        # Clean up extra spaces
        text = text.gsub(/\s{2,}/, " ").strip
        compressed = original_length - text.length

        Result.ok(input.merge(text: text, bytes_compressed: compressed))
      end
    end
  end
end
