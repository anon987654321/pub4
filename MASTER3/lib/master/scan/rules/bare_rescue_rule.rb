# frozen_string_literal: true

module Master
  module Scan
    module Rules
      class BareRescueRule < Rule
        def initialize
          super
          @id          = "bare_rescue"
          @description = "Never use bare rescue -- always specify exception type"
          @severity    = :error
          @axiom_tags  = [:FAIL_VISIBLY]
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb")
          scan_lines(code, /^\s*rescue\s*$/, message: "bare rescue: specify exception type (e.g. rescue StandardError)")
        end
      end
    end
  end
end
