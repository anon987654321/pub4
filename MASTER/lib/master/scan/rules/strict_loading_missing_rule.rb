# frozen_string_literal: true

module Master
  module Scan
    module Rules
      class StrictLoadingMissingRule < Rule
        AR_BASE = /class\s+\w+\s+<\s+(?:ApplicationRecord|ActiveRecord::Base)\b/.freeze
        STRICT  = /\bstrict_loading_by_default\b/.freeze

        def initialize
          super
          @id          = "strict_loading_missing"
          @description = "AR model lacks self.strict_loading_by_default = true — silent N+1s"
          @severity    = :info
          @axiom_tags  = %i[ROBUSTNESS PERFORMANCE]
        end

        def check(code, path:)
          return [] unless path.include?("/app/models/") && path.end_with?(".rb")
          return [] unless code.match?(AR_BASE)
          return [] if code.match?(STRICT)
          line = code.each_line.with_index(1).find { |l, _| l.match?(AR_BASE) }&.last || 1
          [finding(line: line, message: "add `self.strict_loading_by_default = true` to surface missing eager-loads")]
        end
      end
    end
  end
end
