# frozen_string_literal: true

module Master
  module Scan
    module Rules
      class I18nHardcodedStringRule < Rule
        # User-facing string in flash/render/redirect — should be t(...)
        FLASH_LITERAL = /\bflash\[[^\]]+\]\s*=\s*["'][A-Z][^"']{4,}["']/.freeze
        RENDER_TEXT   = /\brender\s+(?:plain|text|html|inline):\s*["'][A-Z][^"']{4,}["']/.freeze
        REDIRECT_NOTICE = /\bredirect_to\s+.+?,\s*notice:\s*["'][A-Z][^"']{4,}["']/.freeze
        REDIRECT_ALERT  = /\bredirect_to\s+.+?,\s*alert:\s*["'][A-Z][^"']{4,}["']/.freeze

        def initialize
          super
          @id          = "i18n_hardcoded_string"
          @description = "Hardcoded user-facing string — wrap in I18n.t(...) for localization"
          @severity    = :info
          @axiom_tags  = %i[ABSTRACTION]
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb") && (path.include?("/app/controllers/") || path.include?("/app/views/"))
          findings = []
          code.each_line.with_index(1) do |line, num|
            next if line.strip.start_with?("#")
            findings << finding(line: num, message: "flash literal — wrap in t('...') for i18n") if line.match?(FLASH_LITERAL)
            findings << finding(line: num, message: "render literal — extract to locale file") if line.match?(RENDER_TEXT)
            findings << finding(line: num, message: "redirect_to notice literal — extract to locale file") if line.match?(REDIRECT_NOTICE)
            findings << finding(line: num, message: "redirect_to alert literal — extract to locale file") if line.match?(REDIRECT_ALERT)
          end
          findings
        end
      end
    end
  end
end
