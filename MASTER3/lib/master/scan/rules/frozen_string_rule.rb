# frozen_string_literal: true

module Master
  module Scan
    module Rules
      class FrozenStringRule < Rule
        def initialize
          super
          @id          = "frozen_string"
          @description = "Ruby files should declare # frozen_string_literal: true"
          @severity    = :warning
          @axiom_tags  = [:PERFORMANCE]
          @auto_fix    = true
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb")
          return [] if code.lines.first&.include?("frozen_string_literal")
          [finding(line: 1, message: "missing # frozen_string_literal: true",
                   fix: "# frozen_string_literal: true\n" + code)]
        end
      end
    end
  end
end
