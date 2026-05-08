# frozen_string_literal: true

module Master
  module Scan
    module Rules
      class RateLimitingRule < Rule
        SENSITIVE = /(login|signup|sign_up|password|reset)/i.freeze

        def initialize
          super
          @id = "rate_limiting"
          @description = "Sensitive endpoints should enforce rate limiting"
          @severity = :error
          @axiom_tags = %i[SECURITY]
        end

        def check(code, path:)
          return [] unless path.include?("/app/controllers/") && path.end_with?(".rb")
          return [] unless path.match?(SENSITIVE) || code.match?(SENSITIVE)
          return [] if code.include?("rate_limit") || code.include?("throttle")
          [finding(line: 1, message: "add rate_limit/throttle protection for sensitive controller actions")]
        end
      end
    end
  end
end
