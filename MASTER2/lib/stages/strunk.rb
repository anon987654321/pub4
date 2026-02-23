# frozen_string_literal: true

module MASTER
  module Stages
    # Stage 7a: Strunk & White filter -- omit needless words from LLM output.
    # Applied after ask, before render. Pure regex -- no extra LLM call.
    class Strunk
      PATTERNS_FILE = File.join(__dir__, "..", "..", "data", "strunk.yml")

      class << self
        def patterns
          @patterns ||= load_patterns
        end

        def load_patterns
          return { preambles: [], hedges: [], endings: [] } unless File.exist?(PATTERNS_FILE)

          data = YAML.safe_load_file(PATTERNS_FILE)
          {
            preambles: Array(data["preambles"]),
            hedges:    Array(data["hedges"]),
            endings:   Array(data["endings"]),
          }
        end
      end

      def call(input)
        text = input[:response].to_s
        return Result.ok(input) if text.empty?

        text = strip_preambles(text)
        text = strip_hedges(text)
        text = strip_endings(text)
        text = strip_markdown(text)
        text = text.strip

        Result.ok(input.merge(response: text))
      end

      private

      # Strip markdown decorations unsuitable for dmesg-style terminal output
      def strip_markdown(text)
        text = text.gsub(/^#+\s+/, '')             # ## headers → plain
        text = text.gsub(/\*\*(.+?)\*\*/m, '\1')  # **bold** → plain
        text = text.gsub(/\*(.+?)\*/m, '\1')       # *italic* → plain
        text = text.gsub(/`{3}[a-z]*\n?/, '')      # fenced code block markers
        text = text.gsub(/^[-*]\s+/, '')            # bullet list markers
        text = text.gsub(/^\d+\.\s+/, '')           # numbered list markers
        text = text.gsub(/\n{3,}/, "\n\n")          # collapse excess blank lines
        # Strip all emoji (broad unicode ranges)
        text = text.gsub(/[\u{1F300}-\u{1FFFF}]|\u{2600}-\u{26FF}|\u{2700}-\u{27BF}/, '')
        text
      end

      def strip_preambles(text)
        self.class.patterns[:preambles].each do |phrase|
          # Remove if it appears as the first sentence (with optional leading whitespace)
          text = text.sub(/\A\s*#{Regexp.escape(phrase)}\s*/i, "")
        end
        text
      end

      def strip_hedges(text)
        self.class.patterns[:hedges].each do |h|
          pat = Regexp.escape(h["pattern"])
          rep = h["replace"].to_s
          text = text.gsub(/#{pat}/i, rep)
        end
        text
      end

      def strip_endings(text)
        self.class.patterns[:endings].each do |phrase|
          text = text.sub(/\s*#{Regexp.escape(phrase)}\s*\z/i, "")
        end
        text
      end
    end
  end
end
