# frozen_string_literal: true

module MASTER
  module Stages
    # Stage 7a: Strunk & White filter -- omit needless words from LLM output.
    # Applied after ask, before render. Pure regex -- no extra LLM call.
    # Code blocks (``` ... ```) and git diffs (+/-/@@) are passed through untouched.
    class Strunk
      PATTERNS_FILE = File.join(__dir__, "..", "..", "data", "strunk.yml")

      # Matches fenced code blocks (``` or ~~~, with optional language tag)
      CODE_BLOCK_RE = /^(`{3,}|~{3,})[^\n]*\n.*?\n\1[ \t]*$/m

      # Matches git diff output (unified diff format)
      DIFF_BLOCK_RE = /^(?:diff --git|--- a\/|\+\+\+ b\/|@@ .+? @@|index [0-9a-f]+\.\.[0-9a-f]+).*/

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

        text = process_preserving_code(text)
        text = text.strip

        Result.ok(input.merge(response: text))
      end

      private

      # Split text into prose and protected segments (code blocks, diffs).
      # Only prose segments get cleaned; protected segments pass through verbatim.
      def process_preserving_code(text)
        segments = []
        rest = text

        while (m = rest.match(CODE_BLOCK_RE))
          before = rest[0, m.begin(0)]
          segments << [:prose, before] unless before.empty?
          segments << [:code,  m[0]]
          rest = rest[m.end(0)..]
        end
        segments << [:prose, rest] unless rest.empty?

        # If text looks like a diff (no fenced blocks but starts with diff headers)
        if segments.all? { |type, _| type == :prose } && text.match?(/\A(?:diff |--- |@@)/m)
          return text
        end

        segments.map do |type, chunk|
          type == :code ? chunk : clean_prose(chunk)
        end.join
      end

      def clean_prose(text)
        text = strip_preambles(text)
        text = strip_hedges(text)
        text = strip_endings(text)
        text = strip_markdown(text)
        text = paraphrase_if_verbose(text)
        text
      end

      # If prose exceeds ~8 lines, paraphrase through the LLM with Strunk & White scrutiny.
      # Preserves all meaning and code references -- no truncation.
      PARAPHRASE_LINE_THRESHOLD = 8

      PARAPHRASE_PROMPT = <<~PROMPT.freeze
        Rewrite the following response applying maximum Strunk & White scrutiny:
        - Omit every needless word. Use active voice. One idea per sentence.
        - No markdown, no headers, no bullet lists, no numbered lists.
        - Preserve every fact, code reference, and file name exactly.
        - Plain prose only. As few lines as possible without losing meaning.

        RESPONSE TO COMPRESS:
      PROMPT

      def paraphrase_if_verbose(text)
        return text if text.lines.count <= PARAPHRASE_LINE_THRESHOLD
        return text unless defined?(LLM) && LLM.configured? && !Thread.current[:llm_quiet]

        result = LLM.ask("#{PARAPHRASE_PROMPT}#{text}", tier: :strong, stream: false)
        result.ok? ? result.value[:content].to_s.strip : text
      rescue StandardError
        text
      end

      # Strip markdown decorations from prose -- never called on code blocks
      def strip_markdown(text)
        text = text.gsub(/^#+\s+/, '')             # ## headers → plain
        text = text.gsub(/\*\*(.+?)\*\*/m, '\1')  # **bold** → plain
        text = text.gsub(/\*(.+?)\*/m, '\1')       # *italic* → plain
        text = text.gsub(/`([^`\n]+)`/, '\1')      # inline `code` → plain (single line only)
        text = text.gsub(/^[-*]\s+/, '')           # bullet list markers
        text = text.gsub(/^\d+\.\s+/, '')          # numbered list markers
        text = text.gsub(/\n{3,}/, "\n\n")         # collapse excess blank lines
        text = text.gsub(/[\u{1F300}-\u{1FFFF}]|\u{2600}-\u{26FF}|\u{2700}-\u{27BF}/, '')
        text
      end

      # Keep only the first 3 non-empty paragraphs -- omit "other options", "which to use", etc.
      def truncate_to_essentials(text)
        paras = text.split(/\n{2,}/).map(&:strip).reject(&:empty?)
        return text if paras.size <= 3

        paras.first(3).join("\n\n")
      end

      def strip_preambles(text)
        self.class.patterns[:preambles].each do |phrase|
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
