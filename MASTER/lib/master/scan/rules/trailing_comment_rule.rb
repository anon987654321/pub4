# frozen_string_literal: true

module Master
  module Scan
    module Rules
      # Flags inline trailing comments whose text restates identifiers already
      # visible in the same line. The name should speak; the comment is noise.
      class TrailingCommentRule < Rule
        INLINE_COMMENT = /^([^#\n]+\S)\s+#\s*(.+)$/.freeze
        NOISE_WORDS    = %w[the a an this that returns gets sets is are be].to_set.freeze

        def initialize
          super
          @id          = "trailing_comment"
          @description = "Trailing comment restates the code — rename instead of annotating"
          @severity    = :style
          @axiom_tags  = [:SELF_EXPLAINING]
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb")
          findings = []
          code.each_line.with_index(1) do |line, num|
            m = line.match(INLINE_COMMENT)
            next unless m

            code_part = m[1]
            comment   = m[2].strip
            next if comment.length > 60
            next unless restatement?(code_part, comment)

            findings << finding(line: num, message: "trailing comment restates the code — remove it or rename the identifier")
          end
          findings
        end

        private

        def restatement?(code_part, comment)
          comment_words = comment.downcase.scan(/[a-z_]+/).reject { |w| NOISE_WORDS.include?(w) }
          return false if comment_words.empty? || comment_words.size > 4
          code_words = code_part.downcase.scan(/[a-z_]+/).to_set
          overlap = comment_words.count { |w| code_words.include?(w) }
          overlap.to_f / comment_words.size >= 0.75
        end
      end
    end
  end
end
