# frozen_string_literal: true

module Shared
  # Deterministic Strunk & White prose strip — ported from MASTER/lib/now/stages/prune.rb.
  # Removes hedges, preambles, markdown noise, and sycophancy without touching code fences.
  class StrunkWhitePass
    FENCE_RE = /(```.*?```)/m.freeze
    HEADER_RE = %r{^\#{1,6}\s+}.freeze
    BOLD_RE = /\*\*(.+?)\*\*/
    ITALIC_RE = /(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)/
    BULLET_RE = /^\s*[-*+]\s+/
    NUMBERED_RE = /^\s*\d+\.\s+/
    HR_RE = /^-{3,}\s*$/
    LINK_RE = /\[([^\]]+)\]\([^)]+\)/
    SYCOPHANCY_RE = /\A\s*(?:
      certainly|of[ ]course|great[ ]question|absolutely|sure|
      happy[ ]to[ ]help|i(?:'d|[ ]would)[ ]be[ ](?:happy|glad)|no[ ]problem
    )[!.,]*\s*/ix

    DEFAULT_RULES = {
      "preambles" => [ "In summary,", "Consequently,", "Therefore,", "Notably,", "Importantly," ],
      "hedges" => [ "I think that", "I believe", "will", "would", "might", "could", "perhaps", "seems", "appears" ],
      "endings" => [ "as a result.", "for this reason.", "thus.", "in effect.", "accordingly." ],
    }.freeze

    REDDIT_NOISE_RE = /
      \[r\/\w+\]\s*|
      scraped\s*&\s*fictivized\s+from\s+reddit[^.]*|
      \bscore:\s*\d+[^.]*|
      \bcomments:\s*\d+[^.]*|
      \breddit\.com\S*
    /ix

    def self.call(text) = new.call(text)

    def call(text)
      prose = text.to_s.strip
      return "" if prose.empty?

      prune_mixed(prose).gsub(REDDIT_NOISE_RE, "").gsub(/\s+/, " ").strip
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
      @rules ||= DEFAULT_RULES
    end
  end
end
