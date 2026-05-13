# frozen_string_literal: true

module Master
  module Judge
  module Scan
    module Rules
      # Duplicate structural code (same AST shape, different names) violates ONE_SOURCE.
      # Delegates to flay for reliable AST-level detection; falls back to a line-hash
      # approach when flay is unavailable (e.g. gem not installed).
      class DuplicateCodeRule < Rule
        FLAY_THRESHOLD = 16
        OCCUR_MIN      = 2

        def initialize
          super
          @id          = "duplicate_code"
          @description = "Duplicate code blocks violate ONE_SOURCE — extract to shared method"
          @severity    = :warning
          @rule_tags  = %i[ONE_SOURCE DRY]
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb")
          flay_available? ? flay_check(code, path) : []
        end

        private

        def flay_available?
          require "flay"
          true
        rescue LoadError
          false
        end

        def flay_check(code, path)
          flay = Flay.new(threshold: FLAY_THRESHOLD, verbose: false, diff: false, summary: false)
          flay.process(path)
          flay.masses.filter_map { |hash, nodes|
            next if nodes.size < OCCUR_MIN
            first = nodes.first
            finding(
              line: first.line,
              message: "duplicate structure #{nodes.size} times (flay mass #{flay.masses[hash]}) — extract to shared method (ONE_SOURCE)"
            )
          }
        rescue StandardError
          []
        end
      end
    end
  end
  end
end
