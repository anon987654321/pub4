# frozen_string_literal: true

module Master
  module Scan
    module Rules
      class I18nCoverageRule < Rule
        LITERAL_TEXT = />\s*[A-Za-z][^<]{3,}</.freeze

        def initialize
          super
          @id = "i18n_coverage"
          @description = "Views should wrap user-facing literals in I18n helpers"
          @severity = :warning
          @axiom_tags = %i[ABSTRACTION]
        end

        def check(code, path:)
          return [] unless path.include?("/app/views/") && path.end_with?(".erb")
          scan_lines(code, LITERAL_TEXT, message: "possible hardcoded UI string; use t('.key')")
        end
      end
    end
  end
end
