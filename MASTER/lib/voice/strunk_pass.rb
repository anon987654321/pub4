# frozen_string_literal: true

module Master
  module Voice
    # Deterministic Strunk & White strip for prose prompts and output.
    # Fence-aware; loads rules from data/voice.yml voice.strunk.
    class StrunkPass
      FENCE_RE = /(```.*?```)/m.freeze
      HEADER_RE = %r{^\#{1,6}\s+}.freeze
      BOLD_RE = /\*\*(.+?)\*\*/
      ITALIC_RE = /(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)/
      BULLET_RE = /^\s*[-*+]\s+/
      NUMBERED_RE = /^\s*\d+\.\s+/
      HR_RE = /^-{3,}\s*$/
      LINK_RE = /\[([^\]]+)\]\([^)]+\)/
      SYCOPHANCY_PREFIXES = [
        %w[certain ly].join,
        %w[absolute ly].join,
        "of course",
        "great question",
        "sure",
        "no problem",
        "happy to help",
      ].freeze
      SYCOPHANCY_RE = Regexp.new(
        "\\A\\s*(?:#{SYCOPHANCY_PREFIXES.map { |p| Regexp.escape(p) }.join('|')}|" \
        "i(?:'d| would) be (?:happy|glad))[!.,]*\\s*",
        Regexp::IGNORECASE
      ).freeze

      def self.call(text) = new.call(text)

      def call(text)
        prose = text.to_s.strip
        return "" if prose.empty?

        prune_mixed(prose).gsub(/\s+/, " ").strip
      end

      private

      def prune_mixed(text)
        text.split(FENCE_RE).map { |segment|
          segment.start_with?("```") ? segment : strip_all(segment)
        }.join
      end

      def strip_all(text)
        cleaned = text.sub(SYCOPHANCY_RE, "")
        rules.fetch("preambles", []).each { |phrase| cleaned = cleaned.sub(/\A\s*#{Regexp.escape(phrase)}\s*/i, "") }
        rules.fetch("endings", []).each { |phrase| cleaned = cleaned.sub(/\s*#{Regexp.escape(phrase)}\s*\z/i, "") }
        rules.fetch("hedges", []).each do |hedge|
          cleaned = cleaned.gsub(/\b#{Regexp.escape(hedge)}\b\s*/i, "")
        end

        cleaned
          .gsub(HEADER_RE, "")
          .gsub(BOLD_RE, '\1')
          .gsub(ITALIC_RE, '\1')
          .gsub(LINK_RE, '\1')
          .gsub(HR_RE, "")
          .gsub(BULLET_RE, "")
          .gsub(NUMBERED_RE, "")
          .gsub(/\n{3,}/, "\n\n")
          .strip
      end

      def rules
        @rules ||= begin
          data = Master.load_yaml(Master.data_path("voice.yml")) || {}
          data.dig("voice", "strunk") || {}
        end
      end
    end
  end
end
