# frozen_string_literal: true

# Simplified persona modes for CLI
module MASTER
  module Unified
    class PersonaMode
      MODES = {
        ronin: {
          max_words: 10,
          style: "terse",
          description: "Minimal output, action-focused"
        },
        verbose: {
          max_words: 500,
          style: "explanatory",
          description: "Detailed explanations, teaching mode"
        },
        hacker: {
          max_words: 100,
          focus: "security",
          style: "paranoid",
          description: "Security-first, assume breach"
        },
        poet: {
          max_words: 50,
          style: "aesthetic",
          description: "Beautiful, metaphorical language"
        },
        detective: {
          max_words: 200,
          focus: "debugging",
          style: "analytical",
          description: "Methodical investigation, evidence-based"
        }
      }.freeze

      attr_reader :current_mode

      def initialize(mode: :verbose)
        @current_mode = mode
      end

      def switch(mode)
        return false unless MODES.key?(mode.to_sym)
        @current_mode = mode.to_sym
        true
      end

      def current
        MODES[@current_mode]
      end

      def max_words
        current[:max_words]
      end

      def style
        current[:style]
      end

      def description
        current[:description]
      end

      def format_output(text)
        case style
        when "terse"
          truncate_to_words(text, max_words)
        when "explanatory"
          text
        when "paranoid"
          add_security_context(text)
        when "aesthetic"
          add_poetic_spacing(text)
        when "analytical"
          add_numbered_points(text)
        else
          text
        end
      end

      def self.list_modes
        MODES.map do |name, config|
          "#{name}: #{config[:description]}"
        end.join("\n")
      end

      private

      def truncate_to_words(text, limit)
        words = text.split(/\s+/)
        return text if words.length <= limit
        
        "#{words[0...limit].join(' ')}..."
      end

      def add_security_context(text)
        "🔒 #{text}"
      end

      def add_poetic_spacing(text)
        text.gsub(/\.\s+/, ".\n\n")
      end

      def add_numbered_points(text)
        lines = text.split("\n")
        return text if lines.length == 1
        
        lines.map.with_index { |line, i| "#{i + 1}. #{line}" }.join("\n")
      end
    end
  end
end
